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

let
  privatePort = 18094;
in
{
  virtualisation.oci-containers.containers."pingvin-share" = {
    # Original Pingvin Share was archived. X is its directly maintained fork.
    # Keep the rolling tag: this homelab deliberately follows current releases,
    # while container-auto-update supplies the failed-start rollback path.
    image = "ghcr.io/smp46/pingvin-share-x:latest";
    environment = {
      "TZ" = "Asia/Tokyo";
      "CONFIG_FILE" = "/opt/app/config.yaml";
      # 発行するリンクに載る URL。これが違うと、渡したリンクが内側の
      # アドレスを指してしまって相手から開けない。
      "APP_URL" = "https://send.gapul.net";
      # トンネルの後ろにいるので、クライアント IP はヘッダから取る。
      "TRUST_PROXY" = "true";
    };
    volumes = [
      "${../../configs/homelab/pingvin-share.yaml}:/opt/app/config.yaml:ro"
      "/var/lib/homelab/pingvin-share/data:/opt/app/backend/data:rw"
    ];
    ports = [ "127.0.0.1:${toString privatePort}:3000/tcp" ];
    log-driver = "journald";
  };
  systemd.services."podman-pingvin-share".serviceConfig.Restart = lib.mkOverride 90 "always";

  systemd.tmpfiles.rules = [
    "d /var/lib/homelab/pingvin-share 0700 root root -"
    # Pingvin drops to uid/gid 1000. SQLite needs directory write access for
    # journals/WAL files, not merely write access to pingvin-share.db itself.
    "d /var/lib/homelab/pingvin-share/data 0700 1000 1000 -"
  ];
}
