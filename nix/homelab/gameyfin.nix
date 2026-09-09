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
  pkgs,
  lib,
  ...
}:
let
  migrateState = pkgs.writeShellScript "gameyfin-state-migrate" ''
    set -eu
    state=/var/lib/homelab/gameyfin
    marker="$state/.v2-state-migrated"
    [ -e "$marker" ] && exit 0

    install -d -m 0700 "$state"
    install -d -m 0755 -o 1337 -g 1337 \
      "$state/db" "$state/data" "$state/plugindata"
    install -d -m 0755 -o 1337 -g 1337 /var/log/gameyfin

    if ${pkgs.podman}/bin/podman container exists gameyfin; then
      was_active=false
      if ${pkgs.systemd}/bin/systemctl is-active --quiet podman-gameyfin.service; then
        was_active=true
        ${pkgs.systemd}/bin/systemctl stop podman-gameyfin.service
      fi
      for dir in db data plugindata; do
        ${pkgs.podman}/bin/podman cp "gameyfin:/opt/gameyfin/$dir/." "$state/$dir/"
      done
      chown -R 1337:1337 "$state/db" "$state/data" "$state/plugindata"
      if [ "$was_active" = true ]; then
        ${pkgs.systemd}/bin/systemctl start podman-gameyfin.service
      fi
    fi
    touch "$marker"
  '';
in
{
  # v2 keeps its state below /opt/gameyfin.  The old v1-era /app/config mount
  # was empty, leaving the H2 database inside the disposable container layer.
  # On the first activation copy that live state out before the container is
  # recreated with the correct mounts.  `podman cp` also works for a stopped
  # container, which makes this safe across the unit restart ordering.
  # Activation runs before systemd reconciles the changed podman unit, while
  # the old container is guaranteed to still exist.  The service is a boot-time
  # fallback for machines restored without an activation-time container.
  system.activationScripts.gameyfinStateMigrate.text = "${migrateState}";

  systemd.services.gameyfin-state-migrate = {
    description = "Preserve Gameyfin v2 state before remounting it";
    before = [ "podman-gameyfin.service" ];
    serviceConfig.Type = "oneshot";
    serviceConfig.ExecStart = migrateState;
  };

  virtualisation.oci-containers.containers."gameyfin" = {
    image = "ghcr.io/gameyfin/gameyfin:latest";
    environment = {
      "TZ" = "Asia/Tokyo";
    };
    # IGDB_CLIENT_ID / IGDB_CLIENT_SECRET。RomM と同じ Twitch のアプリで良い。
    environmentFiles = [ "/var/lib/secrets/gameyfin.env" ];
    volumes = [
      "/var/lib/homelab/gameyfin/db:/opt/gameyfin/db:rw"
      "/var/lib/homelab/gameyfin/data:/opt/gameyfin/data:rw"
      "/var/lib/homelab/gameyfin/plugindata:/opt/gameyfin/plugindata:rw"
      # Logs are operational data, not backup data.  Keep them outside
      # /var/lib so a logging loop cannot fill the Google Drive repository.
      "/var/log/gameyfin:/opt/gameyfin/logs:rw"
      # 読み取り専用で渡す。目録が実体を消せる必要はない。
      "/srv/games/pc:/games:ro"
    ];
    ports = [ "8092:8080/tcp" ];
    log-driver = "journald";
  };
  systemd.services."podman-gameyfin" = {
    after = [ "gameyfin-state-migrate.service" ];
    requires = [ "gameyfin-state-migrate.service" ];
    serviceConfig.Restart = lib.mkOverride 90 "always";
  };

  systemd.tmpfiles.rules = [
    # romm.nix と同じ理由。podman は bind mount の元を作らない。
    "d /var/lib/homelab/gameyfin 0700 root root -"
    "d /var/lib/homelab/gameyfin/db 0755 1337 1337 -"
    "d /var/lib/homelab/gameyfin/data 0755 1337 1337 -"
    "d /var/lib/homelab/gameyfin/plugindata 0755 1337 1337 -"
    "d /var/log/gameyfin 0755 1337 1337 -"
    "d /srv/games/pc 0755 root root -"
  ];

  services.logrotate.settings.gameyfin = {
    files = "/var/log/gameyfin/*.log";
    frequency = "daily";
    size = "50M";
    rotate = 7;
    compress = true;
    copytruncate = true;
    su = "1337 1337";
  };
}
