# YouTube の保存。チャンネルを購読しておくと、新しい動画を勝手に落として置く。
#
# ArchiveBox はページを丸ごと取る道具で、動画は拾えない。消える動画は消える前に
# 手元に無いと戻らないので、別に立てる。
#
# 落とし先を /srv/youtube にしてあるのは、jellyfin が /srv をまるごと /media として
# 見ているから。落ちた時点で棚に並ぶので、Pinchflat 側に閲覧機能を求めなくていい。
# Pinchflat は取ってくる係、jellyfin は見せる係。
#
# /srv は restic の対象外。取り直せるものにバックアップ容量を使わない、という
# movies / tv と同じ扱い。ただし「消えた動画は取り直せない」ので、残したいものが
# はっきりしたら、その分だけ backup.nix の paths に足すこと。
{
  lib,
  ...
}:

{
  virtualisation.oci-containers.containers."pinchflat" = {
    image = "ghcr.io/kieraneglin/pinchflat:latest";
    environment = {
      "TZ" = "Asia/Tokyo";
      # 落としたファイルの所有者。jellyfin が root で動いているので合わせる。
      "UID" = "0";
      "GID" = "0";
    };
    volumes = [
      "/var/lib/homelab/pinchflat:/config:rw"
      "/srv/youtube:/downloads:rw"
    ];
    ports = [ "8098:8945/tcp" ];
    log-driver = "journald";
  };
  systemd.services."podman-pinchflat".serviceConfig.Restart = lib.mkOverride 90 "always";

  systemd.tmpfiles.rules = [
    "d /var/lib/homelab/pinchflat 0700 root root -"
    "d /srv/youtube 0755 root root -"
  ];
}
