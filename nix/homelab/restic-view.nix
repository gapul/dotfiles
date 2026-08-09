{ pkgs, ... }:
let
  resticCommon = import ../lib/restic-common.nix { home = "/root"; };
  mountPoint = "/mnt/restic-view";
in
{
  # files.gapul.net: a read-only window onto the backup repository, for checking
  # from a phone that a file really is in there. It ran on the pve host as a pair
  # of hand-written units and would otherwise have disappeared with it — which
  # matters more now, because backrest's UI is gone too and this would leave no
  # way to look at a backup short of restoring one.
  #
  # restic mount is FUSE and read-only by construction; --no-lock keeps it from
  # interfering with the backup timer writing to the same repository.
  systemd.services.restic-view-mount = {
    description = "restic repository as a read-only FUSE mount";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = with pkgs; [
      restic
      rclone
      fuse
    ];
    environment = {
      RESTIC_REPOSITORY = resticCommon.repository;
      RESTIC_PASSWORD_FILE = "/var/lib/secrets/restic.password";
      RCLONE_CONFIG = "/var/lib/secrets/rclone.conf";
    };
    serviceConfig = {
      ExecStartPre = "-${pkgs.fuse}/bin/fusermount -u ${mountPoint}";
      ExecStart = "${pkgs.restic}/bin/restic mount --no-lock --allow-other --no-default-permissions ${mountPoint}";
      ExecStop = "-${pkgs.fuse}/bin/fusermount -u ${mountPoint}";
      Restart = "on-failure";
      RestartSec = "30s";
    };
    wantedBy = [ "multi-user.target" ];
  };

  systemd.tmpfiles.rules = [ "d ${mountPoint} 0755 root root -" ];
  # --allow-other is what lets filebrowser read a mount owned by root.
  programs.fuse.userAllowOther = true;

  services.filebrowser = {
    enable = true;
    settings = {
      address = "127.0.0.1";
      # Not 8082: that was this service's port when it ran on the pve host, but
      # ntfy's container publishes 8082 here. Two machines' worth of services
      # sharing one port space is the new failure mode in this migration.
      port = 8085;
      root = mountPoint;
    };
  };
  systemd.services.filebrowser = {
    after = [ "restic-view-mount.service" ];
    wants = [ "restic-view-mount.service" ];
  };
}
