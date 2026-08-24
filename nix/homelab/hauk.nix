# 現在地を一時的に他人へ渡す。「今ここにいる」を期限付きの URL で送る道具。
#
# Dawarich と役割が違う。あちらは自分の軌跡を溜めるもの (Google Timeline の代替) で、
# 他人に見せる仕組みではない。こちらは逆に、**位置をディスクに書かない**。セッション
# 中だけ memcached の中にあり、終われば消える。履歴を持たないことが機能。
#
# 以前は Android クライアントしか無くて候補から外れていたが、2026 年に iOS の
# クライアントが出た (App Store の "Hauk"、NickBouwhuis 作)。iOS 18.6 以上。
#
# 相手は tailnet の外にいるので、cal / poll / split と同じくトンネルを通す。
# DNS はこのトンネルの CNAME にすること。
#
# 設定は /var/lib/homelab/hauk/config.php を手で置く (パスワードのハッシュを含むので
# この tree には入れない)。README.md を見ること。
{
  lib,
  ...
}:

{
  virtualisation.oci-containers.containers."hauk" = {
    image = "docker.io/bilde2910/hauk:latest";
    environment = {
      "TZ" = "Asia/Tokyo";
    };
    volumes = [
      "/var/lib/homelab/hauk:/etc/hauk:rw"
    ];
    ports = [ "8095:80/tcp" ];
    log-driver = "journald";
  };
  systemd.services."podman-hauk".serviceConfig.Restart = lib.mkOverride 90 "always";

  systemd.tmpfiles.rules = [
    "d /var/lib/homelab/hauk 0700 root root -"
  ];
}
