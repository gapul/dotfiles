# Gameyfin — a catalog of DRM-free PC games. Put installers bought on GOG or itch.io in
# /srv/games/pc and it scans the folder, attaches IGDB metadata, and lists them.
#
# Two reasons for this over GameVault: the client isn't Windows-only (there are only Macs and
# iPhones here), and all it does is "catalog what's been placed" without imposing its own
# storage format. Files stay in a plain directory, so if it disappoints, delete it and switch tools.
#
# Titles owned on Steam or Epic don't show up here. Their installers can't be kept locally, so
# the only thing to catalog is the fact of ownership, and there's no good self-hosted way to
# track that for now (Playnite is Windows-only).
{
  pkgs,
  lib,
  ...
}:
let
  privatePort = 18092;
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
    # v2 doesn't read the IGDB key from environment variables. It's entered in the admin UI
    # (Administration > Plugins > IGDB Metadata) and stored encrypted in the DB (set on 2026-09-27
    # with the same Twitch app key as RomM). IGDB_* in gameyfin.env is a v1 leftover with no effect.
    environmentFiles = [ "/var/lib/secrets/gameyfin.env" ];
    volumes = [
      "/var/lib/homelab/gameyfin/db:/opt/gameyfin/db:rw"
      "/var/lib/homelab/gameyfin/data:/opt/gameyfin/data:rw"
      "/var/lib/homelab/gameyfin/plugindata:/opt/gameyfin/plugindata:rw"
      # Logs are operational data, not backup data.  Keep them outside
      # /var/lib so a logging loop cannot fill the Google Drive repository.
      "/var/log/gameyfin:/opt/gameyfin/logs:rw"
      # Passed read-only. The catalog has no need to delete the actual files.
      "/srv/games/pc:/games:ro"
    ];
    ports = [ "127.0.0.1:${toString privatePort}:8080/tcp" ];
    log-driver = "journald";
  };
  systemd.services."podman-gameyfin" = {
    after = [ "gameyfin-state-migrate.service" ];
    requires = [ "gameyfin-state-migrate.service" ];
    serviceConfig.Restart = lib.mkOverride 90 "always";
  };

  systemd.tmpfiles.rules = [
    # Same reason as romm.nix. podman doesn't create bind-mount sources.
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
  };
}
