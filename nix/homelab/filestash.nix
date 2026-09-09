{ lib, pkgs, ... }:
let
  stateDir = "/var/lib/homelab/filestash";
  resticMount = "/mnt/restic-view";
  driveMount = "/mnt/google-drive-view";
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

  # Preview replacement for File Browser. Keep it on a separate tailnet-only
  # hostname until the read-only Restic view and Drive connection are verified.
  # The old files.gapul.net remains untouched during that trial.
  virtualisation.oci-containers.containers.filestash = {
    image = "docker.io/machines/filestash:latest";
    environment = {
      # Filestash prepends the request scheme itself; a full URL here produces
      # an invalid https://https://... redirect.
      APPLICATION_URL = "files-preview.gapul.net";
    };
    volumes = [
      "${stateDir}/state:/app/data/state:rw"
      "${resticMount}:/storage/backups:ro"
      "${driveMount}:/storage/drive:rw"
    ];
    ports = [ "127.0.0.1:8099:8334/tcp" ];
    log-driver = "journald";
  };

  systemd.services.podman-filestash = {
    after = [
      "google-drive-view-mount.service"
      "restic-view-mount.service"
    ];
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
