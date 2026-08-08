{
  config,
  pkgs,
  lib,
  ...
}:
# Periodically run restic encrypted backup + integrity check + run monitoring via systemd user timers (for Linux).
# Linux port of the darwin version (home/restic-backup.nix, launchd). Backend, excludes and retention policy are identical.
# Notifications via notify-send (mako), dates via GNU date, targets are Linux XDG directories.
#
# Note (circular dependency): the restic passphrase, age key and ssh key are "keys of this repo itself",
#   so they are not protected by restic. Always store them separately in a password manager (Bitwarden/Ente).
let
  home = config.home.homeDirectory;

  # SSO: shared with the darwin version (restic-backup.nix). nix/lib/restic-common.nix is the sole definition point.
  common = import ../lib/restic-common.nix { inherit home; };

  passwordFile = config.sops.secrets."restic_password".path;
  logFile = "${home}/.local/state/restic/restic-backup.log";

  # The three scripts live in lib/restic-common.nix (shared with the darwin version).
  # Only the Linux-shaped bits are passed in here: notify goes through notify-send (mako),
  # and GNU date parses restic's ISO8601 timestamp directly.
  scripts = common.mkScripts {
    inherit
      pkgs
      lib
      passwordFile
      logFile
      ;
    # Linux XDG directories
    backupPaths = [
      "${home}/Documents"
      "${home}/Pictures"
      "${home}/Downloads"
      "${home}/Music"
      "${home}/Videos"
    ];
    extraPathPkgs = [ pkgs.libnotify ];
    notifyBody = ''notify-send "$1" "$2" 2>/dev/null || true'';
    parseSnapshotTime = ''$(date -d "$latest" +%s 2>/dev/null || echo 0)'';
  };

  # helpers to generate systemd user service + timer
  mkService = desc: script: {
    Unit.Description = desc;
    Service = {
      Type = "oneshot";
      ExecStart = "${script}";
      Nice = 5;
      IOSchedulingClass = "idle";
    };
  };
  mkTimer = desc: onCalendar: {
    Unit.Description = desc;
    Timer = {
      OnCalendar = onCalendar;
      Persistent = true; # run missed executions (sleep/power-off) after boot
    };
    Install.WantedBy = [ "timers.target" ];
  };
in
{
  home.packages = [ pkgs.restic ];

  # restic passphrase (stored in sops defaultSopsFile = secrets/secrets.yaml)
  sops.secrets."restic_password".path = common.passwordFile;

  # env sourced by Justfile / interactive shells (SSO for repo/password/rclone/archiveTag).
  home.file.".config/restic/env".text = common.envFileText;

  systemd.user.services = {
    restic-backup = mkService "restic encrypted backup" scripts.backup;
    restic-check = mkService "restic integrity check" scripts.check;
    restic-monitor = mkService "restic run monitoring" scripts.monitor;
  };
  systemd.user.timers = {
    restic-backup = mkTimer "daily restic backup" "*-*-* 13:00:00";
    restic-check = mkTimer "weekly restic integrity check" "Sun *-*-* 14:00:00";
    restic-monitor = mkTimer "daily restic run monitoring" "*-*-* 19:00:00";
  };
}
