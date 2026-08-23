# 他人にファイルを渡す。WeTransfer の代わり。
#
# 端末間の同期は syncthing と samba で足りているので、埋まっていなかったのは
# 「一度だけ誰かに渡す」方。Nextcloud のような共同作業の箱は要らない。
#
# 期限とダウンロード回数とパスワードを付けたリンクを発行して、期限が来たら実体ごと
# 消える。渡した後に残り続けないことが要点で、そのために自分の箱でやる。
#
# cal / poll / split と同じくトンネルを通す。相手は tailnet の外にいるので、
# caddy の vhost では届かない。DNS はこのトンネルの CNAME にすること。
{
  lib,
  ...
}:

{
  virtualisation.oci-containers.containers."pingvin-share" = {
    image = "ghcr.io/stonith404/pingvin-share:latest";
    environment = {
      "TZ" = "Asia/Tokyo";
      # 発行するリンクに載る URL。これが違うと、渡したリンクが内側の
      # アドレスを指してしまって相手から開けない。
      "APP_URL" = "https://send.gapul.net";
      # トンネルの後ろにいるので、クライアント IP はヘッダから取る。
      "TRUST_PROXY" = "true";
    };
    volumes = [
      "/var/lib/homelab/pingvin-share/data:/opt/app/backend/data:rw"
    ];
    ports = [ "8094:3000/tcp" ];
    log-driver = "journald";
  };
  systemd.services."podman-pingvin-share".serviceConfig.Restart = lib.mkOverride 90 "always";

  systemd.tmpfiles.rules = [
    "d /var/lib/homelab/pingvin-share 0700 root root -"
    "d /var/lib/homelab/pingvin-share/data 0700 root root -"
  ];
}
