# Gameyfin — DRM フリーの PC ゲームの目録。GOG や itch.io で買ったインストーラを
# /srv/games/pc に置くと、フォルダを走査して IGDB のメタデータを付けて並べる。
#
# GameVault ではなくこちらにした理由は 2 つ。クライアントが Windows 専用でないこと
# (ここは Mac と iPhone しかない) と、やることが「置いたものを目録にする」だけで
# 独自のストア形式を持ち込まないこと。ファイルは普通のディレクトリのまま残るので、
# 気に入らなければ消して別の道具に替えられる。
#
# Steam や Epic の所有タイトルはここには並ばない。それらはインストーラを手元に
# 置けないので、目録にできるのは「持っている」という事実だけで、それを自前で
# 追う仕組みは今のところ良いものが無い (Playnite は Windows 専用)。
{
  lib,
  ...
}:

{
  virtualisation.oci-containers.containers."gameyfin" = {
    image = "ghcr.io/gameyfin/gameyfin:latest";
    environment = {
      "TZ" = "Asia/Tokyo";
    };
    # IGDB_CLIENT_ID / IGDB_CLIENT_SECRET。RomM と同じ Twitch のアプリで良い。
    environmentFiles = [ "/var/lib/secrets/gameyfin.env" ];
    volumes = [
      "/var/lib/homelab/gameyfin:/app/config:rw"
      # 読み取り専用で渡す。目録が実体を消せる必要はない。
      "/srv/games/pc:/games:ro"
    ];
    ports = [ "8092:8080/tcp" ];
    log-driver = "journald";
  };
  systemd.services."podman-gameyfin".serviceConfig.Restart = lib.mkOverride 90 "always";

  systemd.tmpfiles.rules = [
    "d /srv/games/pc 0755 root root -"
  ];
}
