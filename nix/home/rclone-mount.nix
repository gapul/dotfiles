{
  config,
  pkgs,
  lib,
  ...
}:
# Mount Google Drive as plaintext under ~/Sync via rclone (macOS only).
# The purpose is "sharing/collaboration with others", not a cold archive. It is unencrypted
# because it should be plainly visible from the Web UI and to those you share with.
#
# Layout: everything replicated somewhere else lives under ~/Sync (2026-08. ~/Cloud is retired).
#   ~/Sync/google-drive-personal  <- remote google-drive-personal:  (remote-primary, a mount)
#   ~/Sync/google-drive-school    <- remote google-drive-school:    (remote-primary, a mount)
#   ~/Sync/syncthing              <- Syncthing share                (local-primary, real files)
# The mount point name is the remote name, so the two never drift apart.
#
# Position in the storage hierarchy:
#   - GitHub                      : reproducible code
#   - restic (warm, untagged)      : irreproducible active files … restic-backup.nix
#   - restic (cold, --tag archive) : files no longer in use (kept forever) … restic-backup.nix + just archive
#   - rclone mount (this file)     : plaintext cloud folder shared with others
#
# Important (protecting the restic repository):
#   Directly under My Drive lives restic-backup/ (the warm+cold encrypted repository).
#   Accidental deletion from a read-write mount would be fatal, so exclude it (--exclude)
#   from the mount's visible range. Excluded paths do not appear on the mount and cannot be deleted.
#
# Prerequisites (harmless if unmet — the agent logs and exits, and launchd does not respawn it):
#   the remote exists in rclone.conf. Create it interactively with
#     rclone config create google-drive-personal drive
#   (re-run when the OAuth token expires).
let
  home = config.home.homeDirectory;
  rcloneConf = "${home}/.config/rclone/rclone.conf";
  cacheDir = "${home}/.cache/rclone";
  logDir = "${home}/Library/Logs/rclone";

  # remote name == mount point name under ~/Sync
  remotes = [
    "google-drive-personal"
    "google-drive-school"
  ];

  rcloneBin = lib.makeBinPath [
    pkgs.rclone
    pkgs.coreutils
  ];

  mountScript =
    name:
    let
      mountPoint = "${home}/Sync/${name}";
      logFile = "${logDir}/${name}.log";
    in
    pkgs.writeShellScript "rclone-mount-${name}" ''
      set -uo pipefail
      export PATH=${rcloneBin}:$PATH
      mkdir -p "${logDir}" "${cacheDir}" "${mountPoint}"

      # Exit 0 when unconfigured. Paired with KeepAlive.SuccessfulExit=false below, launchd leaves it
      # alone instead of respawning a doomed mount every few seconds until the remote is created.
      if [ ! -f "${rcloneConf}" ] || ! grep -q '^\[${name}\]' "${rcloneConf}"; then
        echo "$(date '+%F %T') SKIP: remote ${name} not in ${rcloneConf} (run: rclone config create ${name} drive)" >>"${logFile}"
        exit 0
      fi
      if mount | grep -q " ${mountPoint} "; then
        echo "$(date '+%F %T') already mounted" >>"${logFile}"
        exit 0
      fi

      echo "$(date '+%F %T') mount start" >>"${logFile}"
      # foreground execution (launchd keeps it alive). Exclude the restic repository to protect it:
      # excluded paths don't appear on the mount, so they can't be deleted from Finder either.
      exec rclone mount "${name}:" "${mountPoint}" \
        --config "${rcloneConf}" \
        --exclude "/restic-backup/**" \
        --exclude "/restic-archive/**" \
        --volname "${name}" \
        --vfs-cache-mode writes \
        --dir-cache-time 72h \
        --poll-interval 1m \
        --log-file "${logFile}" \
        --log-level INFO
    '';
in
{
  home.packages = [ pkgs.rclone ];

  # One agent per remote. These used to be hand-written plists in ~/Library/LaunchAgents
  # (com.gapul.rclone.*), which is why the mount points silently kept pointing at the old ~/Cloud.
  launchd.agents = lib.listToAttrs (
    map (name: {
      name = "rclone-${name}";
      value = {
        enable = true;
        config = {
          ProgramArguments = [ "${mountScript name}" ];
          RunAtLoad = true;
          KeepAlive.SuccessfulExit = false; # restart a crashed mount, leave a skipped one alone
          ProcessType = "Background";
          LowPriorityIO = true;
          Nice = 5;
          StandardErrorPath = "${logDir}/${name}.log";
        };
      };
    }) remotes
  );
}
