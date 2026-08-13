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
        {
          PayloadType = "com.apple.caldav.account";
          CalDAVAccountDescription = "Homelab (Radicale)";
          CalDAVHostName = "homeserver.gapul.net";
          CalDAVPort = 5232;
          CalDAVUseSSL = false; # tailnet 内のみで、前段に TLS を置いていない
          CalDAVUsername = user.username;
        }
        {
          PayloadType = "com.apple.carddav.account";
          CardDAVAccountDescription = "Homelab (Radicale)";
          CardDAVHostName = "homeserver.gapul.net";
          CardDAVPort = 5232;
          CardDAVUseSSL = false;
          CardDAVUsername = user.username;
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
