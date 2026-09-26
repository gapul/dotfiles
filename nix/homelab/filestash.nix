{ lib, pkgs, ... }:
let
  stateDir = "/var/lib/homelab/filestash";
  resticMount = "/mnt/restic-view";
  driveMount = "/mnt/google-drive-view";
  prepareConfig = pkgs.writeShellScript "filestash-prepare-config" ''
    set -eu
    umask 077

    state=${stateDir}/state
    config="$state/config/config.json"
    secret=/var/lib/secrets/filestash-secret-key
    admin=/var/lib/secrets/filestash-admin-password
    ${pkgs.coreutils}/bin/install -d -m 0700 ${stateDir}
    ${pkgs.coreutils}/bin/install -d -m 0700 -o 1000 -g 1000 "$state/config"

    # Preserve the key created by the existing GUI-managed installation on the
    # first switch. New installations get an equally opaque local key. The key
    # never enters the Nix store or Git.
    if [ ! -s "$secret" ]; then
      old_secret=""
      if [ -s "$config" ]; then
        old_secret="$(${pkgs.jq}/bin/jq -er '.general.secret_key // empty' "$config" 2>/dev/null || true)"
      fi
      if [ -z "$old_secret" ]; then
        old_secret="$(${pkgs.openssl}/bin/openssl rand -hex 32)"
      fi
      ${pkgs.coreutils}/bin/install -m 0600 /dev/null "$secret"
      printf '%s\n' "$old_secret" > "$secret"
    fi

    # Admin password, same treatment as the signing key: created once on the
    # box, never in the store or Git. Without it Filestash offers /admin/setup
    # to whoever opens the site first (found 2026-09-26). The same password
    # opens the local backends below (plg_backend_local compares against
    # auth.admin), so it is the one credential to keep in Bitwarden.
    if [ ! -s "$admin" ]; then
      ${pkgs.coreutils}/bin/install -m 0600 /dev/null "$admin"
      ${pkgs.openssl}/bin/openssl rand -base64 24 | ${pkgs.coreutils}/bin/tr -d '/+=' > "$admin"
    fi
    admin_pw="$(${pkgs.coreutils}/bin/tr -d '\n' < "$admin")"
    admin_hash="$(${pkgs.apacheHttpd}/bin/htpasswd -nbB "" "$admin_pw" | ${pkgs.coreutils}/bin/cut -d: -f2 | ${pkgs.coreutils}/bin/tr -d '\n')"

    # The two mounts are declared as local backends with the password filled
    # in, so the login page is a click, not a form. Before this the generated
    # config had connections: [] and the UI showed nothing to open.
    tmp="$config.new"
    ${pkgs.jq}/bin/jq -n \
      --arg host 'files.gapul.net' \
      --rawfile secret_key "$secret" \
      --arg admin_hash "$admin_hash" \
      --arg admin_pw "$admin_pw" \
      '{
        general: {host: $host, secret_key: ($secret_key | rtrimstr("\n"))},
        auth: {admin: $admin_hash},
        connections: [
          {type: "local", label: "Google Drive", path: "/storage/drive", password: $admin_pw},
          {type: "local", label: "Backups (restic)", path: "/storage/backups", password: $admin_pw}
        ]
      }' \
      > "$tmp"
    ${pkgs.coreutils}/bin/chown 1000:1000 "$tmp"
    ${pkgs.coreutils}/bin/chmod 0600 "$tmp"
    ${pkgs.coreutils}/bin/mv "$tmp" "$config"
  '';
in
{
  # Reuse the rclone credential that already backs Restic instead of keeping a
  # second Google OAuth token inside Filestash. The encrypted repositories are
  # excluded: they are only meaningful through restic-view-mount below.
  systemd.services.google-drive-view-mount = {
    description = "Google Drive mount for Filestash";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = with pkgs; [
      rclone
      fuse
    ];
    serviceConfig = {
      CacheDirectory = "rclone-filestash";
      ExecStartPre = "-${pkgs.fuse}/bin/fusermount -u ${driveMount}";
      ExecStart = ''
        ${pkgs.rclone}/bin/rclone mount google-drive: ${driveMount} \
          --config /var/lib/secrets/rclone.conf \
          --allow-other \
          --exclude /restic-backup/** \
          --exclude /restic-archive/** \
          --vfs-cache-mode writes \
          --vfs-cache-max-age 24h \
          --vfs-cache-max-size 10Gi \
          --cache-dir /var/cache/rclone-filestash \
          --dir-cache-time 5m \
          --poll-interval 1m
      '';
      ExecStop = "-${pkgs.fuse}/bin/fusermount -u ${driveMount}";
      Restart = "on-failure";
      RestartSec = "30s";
    };
    wantedBy = [ "multi-user.target" ];
  };

  # Filestash has no complete environment-variable schema. Generate its tiny
  # JSON config before each start so the public setting is declarative while the
  # signing key remains outside the Nix store.
  system.activationScripts.filestashConfigMigrate.text = "${prepareConfig}";

  systemd.services.filestash-prepare-config = {
    description = "Render declarative Filestash configuration";
    before = [ "podman-filestash.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = prepareConfig;
    };
  };

  # File Browser replacement. One UI exposes Google Drive and the read-only
  # Restic mount without moving either data source.
  virtualisation.oci-containers.containers.filestash = {
    image = "docker.io/machines/filestash:latest";
    environment = {
      # Filestash prepends the request scheme itself; a full URL here produces
      # an invalid https://https://... redirect.
      APPLICATION_URL = "files.gapul.net";
    };
    volumes = [
      "${stateDir}/state:/app/data/state:rw"
      "${resticMount}:/storage/backups:ro"
      "${driveMount}:/storage/drive:rw"
    ];
    ports = [ "127.0.0.1:18099:8334/tcp" ];
    log-driver = "journald";
  };

  systemd.services.podman-filestash = {
    after = [
      "filestash-prepare-config.service"
      "google-drive-view-mount.service"
      "restic-view-mount.service"
    ];
    requires = [ "filestash-prepare-config.service" ];
    wants = [
      "google-drive-view-mount.service"
      "restic-view-mount.service"
    ];
    serviceConfig.Restart = lib.mkOverride 90 "always";
  };

  systemd.tmpfiles.rules = [
    "d ${stateDir} 0700 root root -"
    # The official image deliberately runs as its unprivileged filestash user.
    "d ${stateDir}/state 0700 1000 1000 -"
    "d ${driveMount} 0755 root root -"
  ];
}
