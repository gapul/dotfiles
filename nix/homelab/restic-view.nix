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
      # Since restic 0.19 a cache location is mandatory, and if it can't find one it refuses to
      # start with "unable to locate cache directory: neither $XDG_CACHE_HOME nor $HOME are
      # defined". systemd units have no HOME, so set it explicitly.
      # CacheDirectory below creates /var/cache/restic, so match that.
      XDG_CACHE_HOME = "/var/cache";
    };
    serviceConfig = {
      # restic accumulates the index here. Without it, the repository is re-read every time, so
      # even just browsing is slow. --no-cache would silence it, but that only hides the symptom
      # and hits Google Drive on every browse.
      CacheDirectory = "restic";
      ExecStartPre = "-${pkgs.fuse}/bin/fusermount -u ${mountPoint}";
      ExecStart = "${pkgs.restic}/bin/restic mount --no-lock --allow-other --no-default-permissions ${mountPoint}";
      ExecStop = "-${pkgs.fuse}/bin/fusermount -u ${mountPoint}";
      Restart = "on-failure";
      RestartSec = "30s";
    };
    wantedBy = [ "multi-user.target" ];
  };

  systemd.tmpfiles.rules = [ "d ${mountPoint} 0755 root root -" ];
  # --allow-other is what lets Filestash read a mount owned by root.
  programs.fuse.userAllowOther = true;
}
