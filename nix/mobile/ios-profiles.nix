# iOS の構成プロファイル (.mobileconfig) を宣言から生成する。
#
# .mobileconfig は XML plist でしかないので、payload を nix の attrset で書いて
# pkgs.formats.plist に流せば済む。生成した先を iPhone に届けるところは
# mobile/ios/profiles/serve.sh。
#
# nix にできるのは生成まで。適用は端末側の手作業になる (監視モードを掛けるか
# MDM を建てない限り、外からプロファイルを押し込む API が iOS に無い)。
{
  pkgs,
  lib,
  user,
}:
let
  plist = pkgs.formats.plist { };

  # 文字列から決定的に UUID を作る。iOS はプロファイルを PayloadUUID で同定するので、
  # ここが毎回変わると更新のたびに別物として端末に積み上がる。ハッシュから引くことで
  # 「名前が同じなら UUID も同じ」を保つ。
  uuidOf =
    s:
    let
      h = builtins.hashString "sha256" s;
      part = offset: len: lib.substring offset len h;
    in
    lib.toUpper "${part 0 8}-${part 8 4}-${part 12 4}-${part 16 4}-${part 20 12}";

  # payload 側の定型 (バージョン / 識別子 / UUID) を埋めて Configuration で包む。
  mkProfile =
    name:
    {
      displayName,
      description,
      payloads,
    }:
    {
      PayloadType = "Configuration";
      PayloadVersion = 1;
      PayloadIdentifier = "net.gapul.${name}";
      PayloadUUID = uuidOf name;
      PayloadDisplayName = displayName;
      PayloadDescription = description;
      PayloadRemovalDisallowed = false;
      PayloadContent = lib.imap0 (
        i: payload:
        payload
        // {
          PayloadVersion = 1;
          PayloadIdentifier = "net.gapul.${name}.${toString i}";
          PayloadUUID = uuidOf "${name}.${toString i}";
        }
      ) payloads;
    };

  # ベンダーが署名済みで配っているものはここに書かない (NextDNS の DNS プロファイルも
  # Tailscale の VPN プロファイルも本家が配っている)。配布元が無いものだけ。
  profiles = {
    homelab-dav = {
      displayName = "Homelab CalDAV/CardDAV";
      description = "自宅 Radicale のカレンダーと連絡先。パスワードは初回に端末が訊く。";
      payloads = [
        # 宛先は radicale の 5232 を直接ではなく hosts/homeserver.nix の sites 表が
        # 立てている dav の vhost。Caddy が ACME 証明書で終端しているので、
        # 資格情報が平文で流れない。A レコードは tailnet アドレスを指しているため、
        # tailnet に入っていないと名前が引けても届かない。
        {
          PayloadType = "com.apple.caldav.account";
          CalDAVAccountDescription = "Homelab (Radicale)";
          CalDAVHostName = "dav.gapul.net";
          CalDAVUseSSL = true;
          CalDAVUsername = user.username;
        }
        {
          PayloadType = "com.apple.carddav.account";
          CardDAVAccountDescription = "Homelab (Radicale)";
          CardDAVHostName = "dav.gapul.net";
          CardDAVUseSSL = true;
          CardDAVUsername = user.username;
        }
      ];
    };
    # The three Stalwart mailboxes (homelab/mail.nix). The same file installs on macOS
    # for Mail.app. As with CalDAV vs CardDAV, Apple has no payload type that bundles
    # accounts. Outgoing points at Stalwart too, but it has no submission listener
    # yet, so this is read-only in practice.
    homelab-mail = {
      displayName = "Homelab Mail";
      description = "自宅 Stalwart の IMAP 口座 (gmail / work / school の写し)。パスワードは初回に端末が訊く。";
      payloads =
        map
          (name: {
            PayloadType = "com.apple.mail.managed";
            EmailAccountDescription = "Homelab (${name} mirror)";
            EmailAccountType = "EmailTypeIMAP";
            EmailAddress = "${name}@mail.gapul.net";
            IncomingMailServerHostName = "mail.gapul.net";
            IncomingMailServerPortNumber = 993;
            IncomingMailServerUseSSL = true;
            IncomingMailServerAuthentication = "EmailAuthPassword";
            IncomingMailServerUsername = name;
            OutgoingMailServerHostName = "mail.gapul.net";
            OutgoingMailServerPortNumber = 465;
            OutgoingMailServerUseSSL = true;
            OutgoingMailServerAuthentication = "EmailAuthPassword";
            OutgoingMailServerUsername = name;
            OutgoingPasswordSameAsIncomingPassword = true;
          })
          [
            "gmail"
            "work"
            "school"
          ];
    };
    # 自宅の blocky を iOS の暗号化 DNS (DoH) として登録する。hosts/homeserver.nix の dns2
    # vhost が Caddy で TLS 終端し、blocky の HTTP ポートの /dns-query に流す。以前は
    # NextDNS の配布プロファイルがこの役だった (2026-09-26 に blocky へ一本化)。
    # dns2.gapul.net は tailnet アドレスを指すので、Tailscale が切れていると届かない。
    # ServerAddresses は名前が引けない状態でも到達できるようにする IP のヒント。
    homelab-dns = {
      displayName = "Homelab DNS (blocky)";
      description = "自宅 blocky を DNS over HTTPS で使う。広告・トラッカー遮断は nix/lib/blocky-settings.nix。";
      payloads = [
        {
          PayloadType = "com.apple.dnsSettings.managed";
          DNSSettings = {
            DNSProtocol = "HTTPS";
            ServerURL = "https://dns2.gapul.net/dns-query";
            ServerAddresses = [ "100.127.129.31" ];
          };
          ProhibitDisablement = false;
        }
      ];
    };
  };
in
pkgs.linkFarm "ios-profiles" (
  lib.mapAttrsToList (name: profile: {
    name = "${name}.mobileconfig";
    path = plist.generate "${name}.mobileconfig" (mkProfile name profile);
  }) profiles
)
