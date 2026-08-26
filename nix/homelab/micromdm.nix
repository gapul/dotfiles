# MDM。Apple の端末に設定プロファイルを配る。
#
# 動機は 2 つある。
#
# 1. TCC の許可を宣言にする。フルディスクアクセスとアクセシビリティは PPPC
#    ペイロードで無言に付与できる。**画面収録はできない** — macOS 側の制限で、
#    MDM にできるのは拒否か「標準ユーザーに承認させる」までなので、初回だけは
#    人が押す。毎月の再承認 (macOS 15 以降) は Restrictions の
#    forceBypassScreenCaptureAlert で抑えられる。
#
#    重要: TCC のペイロードは **MDM 経由で配られたときだけ有効**。手で
#    ダブルクリックしたプロファイルでは効かない。だからこのサーバが要る。
#
# 2. iPhone の設定プロファイル (CalDAV / CardDAV / メール) を push する。今は
#    scripts/gen-apple-profile.py が吐いたものを手で入れている。secrets を
#    変えるたびに作り直して入れ直しになっていた。
#
# NanoMDM ではなく MicroMDM なのは、nixpkgs に入っていて SCEP を内蔵している
# から。台数が 2-3 台の個人用途だと、部品が少ない方が保守が楽になる。
#
# 端末は外からも check-in する (家の外で電源を入れたときなど) ので、caddy の
# vhost ではなく cloudflared のトンネルを通す。DNS はトンネルの CNAME。
{
  pkgs,
  ...
}:
let
  # api-key はフラグでしか渡せない (このバージョンは環境変数を読まない)。
  # つまり `ps` に見える。緩和として API は 127.0.0.1 に閉じ、鍵は 0400 で
  # root だけが読む。台数と用途を考えて許容しているが、環境変数対応が入ったら
  # そちらに移すこと。
  startScript = pkgs.writeShellScript "micromdm-start" ''
    set -eu
    exec ${pkgs.micromdm}/bin/micromdm serve \
      -server-url https://mdm.gapul.net \
      -config-path /var/lib/micromdm \
      -http-addr 127.0.0.1:8099 \
      -tls=false \
      -http-proxy-headers \
      -homepage=false \
      -api-key "$(cat /var/lib/secrets/micromdm.api-key)"
  '';
in
{
  systemd.services.micromdm = {
    description = "MicroMDM (Apple 端末の設定プロファイル配布)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      ExecStart = startScript;
      Restart = "always";
      RestartSec = 10;
      StateDirectory = "micromdm";
      # APNs の証明書と SCEP の鍵を置くので、他は触らせない。
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ReadWritePaths = [ "/var/lib/micromdm" ];
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/micromdm 0700 root root -"
  ];
}
