# A drill that actually restores from backup. Once a month.
#
# backup.nix is the taking side, and restic check verifies repository integrity. Neither answers
# "can it be restored?". That is exactly what surfaced in 2026-08: a running postgres was being
# copied as files, and although the transfer succeeded daily, there was no guarantee it could be
# restored. It was fixed to take dumps, but the fix itself has not been verified.
#
# You can see by eye that a dump is in the snapshot. That is "the file exists", not "it can be
# restored". This does the latter: it starts a throwaway postgres and really runs pg_restore.
{
  pkgs,
  ...
}:
{
  systemd.services.restore-drill = {
    description = "バックアップから実際に復元してみる";
    path = with pkgs; [
      restic
      rclone
      podman
      sqlite
      curl
      coreutils
      gnugrep
      hostname
    ];
    environment = {
      RESTIC_REPOSITORY = (import ../lib/restic-common.nix { home = "/root"; }).repository;
      RESTIC_PASSWORD_FILE = "/var/lib/secrets/restic.password";
      RCLONE_CONFIG = "/var/lib/secrets/rclone.conf";
      # restic 0.19 requires a cache location even for a one-shot restore.
      XDG_CACHE_HOME = "/var/cache";
    };
    serviceConfig = {
      Type = "oneshot";
      CacheDirectory = "restic";
      ExecStart = "${pkgs.bash}/bin/bash ${../../configs/homelab/restore-drill.sh}";
      # Starts a throwaway postgres and expands a few hundred MB. The time is kept away from 03:00
      # so it doesn't collide with the backup itself.
      TimeoutStartSec = "60min";
    };
    onFailure = [ "ntfy-failure@%n.service" ];
  };

  systemd.timers.restore-drill = {
    description = "復元訓練を月に1回";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "monthly";
      # No need for everything to fire at the start of the month. A time that avoids the backup (03:00).
      RandomizedDelaySec = "6h";
      Persistent = true;
    };
  };
}
