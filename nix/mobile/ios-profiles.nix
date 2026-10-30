# Generate iOS configuration profiles (.mobileconfig) declaratively.
#
# A .mobileconfig is just an XML plist, so writing the payload as a nix attrset and feeding
# it to pkgs.formats.plist is enough. Delivering the output to the iPhone is
# mobile/ios/profiles/serve.sh.
#
# nix can only go as far as generating. Installing is manual on the device (iOS has no API
# for pushing profiles from outside unless the device is supervised or an MDM is set up).
#
# The mail profiles carry no password here, since the output lands in the world-readable store.
# mobile/ios/profiles/mail.sh (`just mail-profiles`) copies them out and fills the passwords in
# from sops, so a device gets them without typing anything.
{
  pkgs,
  lib,
  user,
}:
let
  plist = pkgs.formats.plist { };

  # Derive a UUID deterministically from a string. iOS identifies profiles by PayloadUUID, so
  # if this changed every time, each update would pile up on the device as a separate profile.
  # Deriving it from a hash keeps "same name, same UUID".
  uuidOf =
    s:
    let
      h = builtins.hashString "sha256" s;
      part = offset: len: lib.substring offset len h;
    in
    lib.toUpper "${part 0 8}-${part 8 4}-${part 12 4}-${part 16 4}-${part 20 12}";

  # Fill in the payload boilerplate (version / identifier / UUID) and wrap it in a Configuration.
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

  # Don't put profiles here that the vendor distributes signed (NextDNS's DNS profile and
  # Tailscale's VPN profile are both distributed by upstream). Only ones with no distributor.
  profiles = {
    homelab-dav = {
      displayName = "Homelab CalDAV/CardDAV";
      description = "自宅 Radicale のカレンダーと連絡先。パスワードは初回に端末が訊く。";
      payloads = [
        # The target is not radicale's 5232 directly but the dav vhost set up by the sites
        # table in hosts/homeserver.nix. Caddy terminates it with an ACME certificate, so
        # credentials don't travel in plaintext. The A record points at a tailnet address, so
        # without being on the tailnet the name resolves but is unreachable.
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
    # gapul.net's MX stays on Cloudflare Email Routing (Sakura's mailbox plan has no
    # catch-all), which forwards every address to this one Sakura mailbox. Sending goes
    # out through Sakura too, and it accepts any @gapul.net as From, so replying from an
    # alias only needs that alias added to the account's address list on the device.
    sakura-mail = {
      displayName = "gapul.net Mail";
      description = "gapul.net のメール (さくらのメールボックス、全アドレスがここに届く)。パスワードは just mail-profiles 経由なら入っていて、そうでなければ初回に端末が訊く。";
      payloads = [
        {
          PayloadType = "com.apple.mail.managed";
          EmailAccountDescription = "gapul.net";
          EmailAccountType = "EmailTypeIMAP";
          EmailAddress = "gapul@gapul.net";
          IncomingMailServerHostName = "gapul.sakura.ne.jp";
          IncomingMailServerPortNumber = 993;
          IncomingMailServerUseSSL = true;
          IncomingMailServerAuthentication = "EmailAuthPassword";
          IncomingMailServerUsername = "gapul@gapul.sakura.ne.jp";
          OutgoingMailServerHostName = "gapul.sakura.ne.jp";
          OutgoingMailServerPortNumber = 465;
          OutgoingMailServerUseSSL = true;
          OutgoingMailServerAuthentication = "EmailAuthPassword";
          OutgoingMailServerUsername = "gapul@gapul.sakura.ne.jp";
          OutgoingPasswordSameAsIncomingPassword = true;
        }
      ];
    };
    homelab-mail = {
      displayName = "Homelab Mail";
      description = "自宅 Stalwart の IMAP 口座 (gmail / sean / school の写し)。パスワードは just mail-profiles 経由なら入っていて、そうでなければ初回に端末が訊く。";
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
            "sean"
            "school"
          ];
    };
    # Register the home blocky as iOS encrypted DNS (DoH). The dns2 vhost in hosts/homeserver.nix
    # terminates TLS in Caddy and forwards to /dns-query on blocky's HTTP port. The NextDNS
    # distributed profile used to fill this role (consolidated onto blocky on 2026-09-26).
    # dns2.gapul.net points at a tailnet address, so it's unreachable when Tailscale is down.
    # ServerAddresses are IP hints that keep it reachable even when the name can't be resolved.
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

  # Fonts for scripts iOS's built-in fonts cannot render. Checked on 2026-10-30 against the
  # fonts Apple's system font list (developer.apple.com/fonts/system-fonts) marks as installed
  # on iOS: hentaigana, Tangut, Khitan Small Script, Nushu and CJK Extensions B–J had no glyphs
  # at all. Installed fonts are certain to show up in apps with a font picker (Pages and the
  # like); whether apps without one fall back to them is up to the app.
  #
  # Lockdown Mode refuses to install any profile, so turn it off for the install and back on
  # afterwards.
  noto = "${pkgs.noto-fonts}/share/fonts/noto";
  # Supplements CJK Extensions B–J only (P1 = SIP, P2 = TIP); the basic block and Extension A
  # are left to the system's CJK fonts. Dual-licensed MIT / OFL-1.1.
  plangothic =
    part: hash:
    pkgs.fetchurl {
      url = "https://github.com/Fitzgerald-Porthmouth-Koenigsegg/Plangothic_Project/releases/download/V2.9.5795/Plangothic${part}-Regular.ttf";
      inherit hash;
    };
  fontProfiles = {
    font-hentaigana = {
      displayName = "Noto Serif Hentaigana";
      description = "変体仮名 (Unicode の Kana Supplement / Extended-A)。";
      fonts = [
        "${noto}/NotoSerifHentaigana-Regular.otf"
        "${noto}/NotoSerifHentaigana-Bold.otf"
      ];
    };
    font-tangut-khitan-nushu = {
      displayName = "西夏文字・契丹小字・女書 (Noto)";
      description = "Noto Serif Tangut / Noto Serif Khitan Small Script / Noto Sans Nushu。";
      fonts = [
        "${noto}/NotoSerifTangut-Regular.otf"
        "${noto}/NotoSerifKhitanSmallScript-Regular.otf"
        "${noto}/NotoSansNushu-Regular.otf"
      ];
    };
    font-plangothic = {
      displayName = "Plangothic (拡張漢字)";
      description = "CJK 統合漢字の拡張 B〜J。基本ブロックと拡張 A はシステムのフォントに任せる。";
      fonts = [
        (plangothic "P1" "sha256-VQtdB3WxVAWUaxj0hD30OaUeaVCNfmd42UwfelPcWtY=")
        (plangothic "P2" "sha256-aBkzNwrf4PxyU/d3NSdagv6gn+T4rbqQe960bBENr48=")
      ];
    };
  };

  # A com.apple.font payload carries the font file as <data>, which pkgs.formats.plist has no
  # way to express (every nix string comes out as <string>). So the boilerplate is still filled
  # in by mkProfile, and python's plistlib swaps each font path for the file's bytes.
  generateFontProfile =
    name:
    {
      displayName,
      description,
      fonts,
    }:
    let
      spec = pkgs.writeText "${name}.json" (
        builtins.toJSON (
          mkProfile name {
            inherit displayName description;
            payloads = map (font: {
              PayloadType = "com.apple.font";
              # A fetchurl output is named <hash>-<file>; the device shows Name, so drop the hash.
              Name = lib.last (builtins.match "([0-9a-z]{32}-)?(.*)" (baseNameOf font));
              Font = "${font}";
            }) fonts;
          }
        )
      );
    in
    pkgs.runCommand "${name}.mobileconfig" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      python3 -I - ${spec} "$out" <<'EOF'
      import json, plistlib, sys
      spec, out = sys.argv[1:]
      profile = json.load(open(spec))
      for payload in profile["PayloadContent"]:
          payload["Font"] = open(payload["Font"], "rb").read()
      with open(out, "wb") as f:
          plistlib.dump(profile, f)
      EOF
    '';
in
pkgs.linkFarm "ios-profiles" (
  lib.mapAttrsToList (name: profile: {
    name = "${name}.mobileconfig";
    path = plist.generate "${name}.mobileconfig" (mkProfile name profile);
  }) profiles
  ++ lib.mapAttrsToList (name: profile: {
    name = "${name}.mobileconfig";
    path = generateFontProfile name profile;
  }) fontProfiles
)
