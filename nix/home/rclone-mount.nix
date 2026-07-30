{
  config,
  pkgs,
  lib,
  ...
}:
# Mount Google Drive (My Drive) as plaintext at ~/Cloud/GoogleDrive via rclone (macOS only).
# The purpose is "sharing/collaboration with others", not a cold archive. It is unencrypted
# because it should be plainly visible from the Web UI and to those you share with.
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
# The mount method is rclone nfsmount (rclone's built-in NFS server + macOS's standard NFS client).
#   A fully FOSS method using no FUSE/KEXT/fuse-t at all. Removes the proprietary fuse-t dependency.
#   Note (NFS method quirks): atime/mtime cannot be set individually, and browsing in Finder can
#   update mtime, causing rclone to re-upload the whole thing. Writes under --read-only fail silently.
#   Also, restic mount (browsing the archive) is not possible with this method because bazil/fuse
#   hits the macFUSE KEXT directly. Browse via just archive-ls / archive-find instead.
#
# Prerequisites (harmless if unmet — the mount is simply skipped):
#   1. rclone google-drive: is enabled (re-authenticate when the token expires). No extra software/KEXT needed
let
  home = config.home.homeDirectory;

  remote = "google-drive:"; # My Drive root (plaintext)
  mountPoint = "${home}/Cloud/GoogleDrive";
  rcloneConf = "${home}/.config/rclone/rclone.conf";
  cacheDir = "${home}/.cache/rclone";
  logFile = "${home}/Library/Logs/rclone-gdrive.log";

  rcloneBin = lib.makeBinPath [
    pkgs.rclone
    pkgs.coreutils
  ];

  notify = ''notify() { /usr/bin/osascript -e "display notification \"$2\" with title \"$1\"" 2>/dev/null || true; }'';

  mountScript = pkgs.writeShellScript "rclone-gdrive-mount" ''
    set -uo pipefail
    export PATH=${rcloneBin}:/usr/local/bin:$PATH
    mkdir -p "$(dirname ${logFile})" "${cacheDir}" "${mountPoint}"

    if [ ! -f "${rcloneConf}" ]; then
      echo "$(date '+%F %T') SKIP: ${rcloneConf} missing (sops not deployed)" >>"${logFile}"
      exit 0
    fi
    if mount | grep -q " ${mountPoint} "; then
      echo "$(date '+%F %T') already mounted" >>"${logFile}"
      exit 0
    fi

    echo "$(date '+%F %T') mount start" >>"${logFile}"
    # foreground execution (managed by launchd via KeepAlive). Exclude the restic repository to protect it.
    # rclone nfsmount: mount using rclone's built-in NFS server + macOS's standard NFS client,
    # using no FUSE/KEXT/fuse-t at all (fully FOSS). fuse-t-specific -o/--volname is unnecessary.
    exec rclone nfsmount "${remote}" "${mountPoint}" \
      --config "${rcloneConf}" \
      --exclude "/restic-backup/**" \
      --exclude "/restic-archive/**" \
      --vfs-cache-mode full \
      --vfs-cache-max-size 5G \
      --vfs-cache-max-age 168h \
      --dir-cache-time 72h \
      --poll-interval 1m \
      --log-file "${logFile}" \
      --log-level INFO
  '';

  # mount health check (daily). Notify if it is down (same idea as restic-monitor)
  monitorScript = pkgs.writeShellScript "rclone-gdrive-monitor" ''
    set -uo pipefail
    ${notify}
    if ! mount | grep -q " ${mountPoint} "; then
      notify "☁️ GoogleDrive not mounted" "~/Cloud/GoogleDrive is detached. Log: ${logFile}"
      exit 0
    fi
    # also detect the case where it is mounted but unreadable (stale)
    if ! /bin/ls "${mountPoint}" >/dev/null 2>&1; then
      notify "☁️ GoogleDrive not responding" "Mount exists but is unreadable (possibly stale)"
    fi
  '';
in
{
  home.packages = [ pkgs.rclone ];

  launchd.agents = {
    # The old ~/Cloud/GoogleDrive mount is retired.
    # personal/school are now mounted separately via a manually managed LaunchAgent:
    #   ~/Cloud/GoogleDrive-personal -> google-drive-personal:
    #   ~/Cloud/GoogleDrive-school   -> google-drive-school:
    rclone-gdrive = {
      enable = false;
      config = {
        ProgramArguments = [ "${mountScript}" ];
        RunAtLoad = true;
        KeepAlive = true;
        ProcessType = "Background";
        LowPriorityIO = true;
        Nice = 5;
        StandardErrorPath = "${logFile}";
      };
    };
    # The old ~/Cloud/GoogleDrive health check is also retired.
    rclone-gdrive-monitor = {
      enable = false;
      config = {
        ProgramArguments = [ "${monitorScript}" ];
        StartCalendarInterval = [
          {
            Hour = 19;
            Minute = 30;
          }
        ];
        RunAtLoad = false;
        ProcessType = "Background";
      };
    };
  };
}
