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
#   ~/Sync/google-drive           <- remote google-drive:           (remote-primary, a mount, personal)
#   ~/Sync/google-drive-school    <- remote google-drive-school:    (remote-primary, a mount)
#   ~/Sync/google-drive-work      <- remote google-drive-work:      (remote-primary, a mount, company)
#   ~/Sync/syncthing              <- Syncthing share                (local-primary, real files)
#   ~/Sync/<ssh-host>             <- mutagen session                (peer-primary, home/mutagen-sync.nix)
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
#   the remote exists in rclone.conf. Note that rclone.conf is a symlink into the sops-nix secret
#   (home/secrets.nix, key rclone_conf), so `rclone config create` writes are thrown away at the
#   next activation. Get a token with `rclone authorize drive` and put the section into
#   secrets/secrets.yaml instead.
let
  home = config.home.homeDirectory;
  rcloneConf = "${home}/.config/rclone/rclone.conf";
  cacheDir = "${home}/.cache/rclone";
  logDir = "${home}/Library/Logs/rclone";

  # remote name == mount point name under ~/Sync
  remotes = [
    # The personal account is the existing "google-drive" remote (also the restic backend).
    # Do not duplicate it as google-drive-personal: two sections sharing one OAuth token means
    # two writers racing to refresh it in a single rclone.conf.
    "google-drive"
    "google-drive-school"
    # Company Workspace account. My Drive only; the "ISMS Docs" shared drive is not mounted
    # (that needs its own section with team_drive set).
    "google-drive-work"
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
      # An entry in `mount` does not mean the mount works. rclone is its own NFS server, so when it
      # dies the entry lingers with nothing behind it, and everything that touches the path blocks
      # in uninterruptible wait — including Spotlight's mds, which takes every mdfind on the machine
      # down with it (2026-08-10: the school mount sat stale for 7h because this branch kept
      # reporting "already mounted"). Treat it as live only while an rclone is still serving it.
      if mount | grep -q " ${mountPoint} "; then
        if pgrep -f "nfsmount ${name}: ${mountPoint}" >/dev/null; then
          echo "$(date '+%F %T') already mounted" >>"${logFile}"
          exit 0
        fi
        echo "$(date '+%F %T') stale mount left by a dead rclone, unmounting" >>"${logFile}"
        umount -f "${mountPoint}" >>"${logFile}" 2>&1
        # Give up rather than let launchd respawn against an occupied mount point every few seconds.
        if mount | grep -q " ${mountPoint} "; then
          echo "$(date '+%F %T') SKIP: could not unmount ${mountPoint} (try: sudo umount -f)" >>"${logFile}"
          exit 0
        fi
      fi

      echo "$(date '+%F %T') mount start" >>"${logFile}"
      # foreground execution (launchd keeps it alive). Exclude the restic repository to protect it:
      # excluded paths don't appear on the mount, so they can't be deleted from Finder either.
      # nfsmount, not mount: `rclone mount` needs macFUSE, a kext that costs a reboot and a
      # security approval. nfsmount serves the VFS over rclone's built-in NFS server and calls
      # mount_nfs, which needs neither root nor a third-party filesystem.
      # Not exec'd: the shell has to outlive rclone to clean up after it. launchd stops these
      # agents on every home-manager activation, and rclone leaves the NFS mount entry behind when
      # it goes. Until the agent comes back, the kernel holds a mount pointed at a dead server —
      # it logs "nfs server localhost:/<remote>: not responding" every few seconds, and everything
      # that so much as stats the path (ls, ps, Spotlight's mds, and therefore every mdfind on the
      # machine) blocks in uninterruptible wait. The startup path above already knows how to clear
      # a stale entry; doing it here instead means it never exists in the first place.
      rclone nfsmount "${name}:" "${mountPoint}" \
        --config "${rcloneConf}" \
        --exclude "/restic-backup/**" \
        --exclude "/restic-archive/**" \
        --volname "${name}" \
        --vfs-cache-mode writes \
        --dir-cache-time 72h \
        --poll-interval 1m \
        --log-file "${logFile}" \
        --log-level INFO &
      rclone_pid=$!

      # Unmount only after rclone has exited, never before: it owns the write-back cache, so
      # pulling the mount out from under a live one is how you lose the writes it still holds.
      cleanup() {
        kill -TERM "$rclone_pid" 2>/dev/null
        wait "$rclone_pid" 2>/dev/null
        if mount | grep -q " ${mountPoint} "; then
          umount -f "${mountPoint}" >>"${logFile}" 2>&1
        fi
        echo "$(date '+%F %T') stopped, mount released" >>"${logFile}"
        exit 0
      }
      trap cleanup TERM INT

      wait "$rclone_pid"
      # rclone died on its own (crash, or the remote went away). Same cleanup, so KeepAlive
      # restarts against a free mount point rather than the "could not unmount" dead end above.
      status=$?
      if mount | grep -q " ${mountPoint} "; then
        umount -f "${mountPoint}" >>"${logFile}" 2>&1
      fi
      echo "$(date '+%F %T') rclone exited ($status), mount released" >>"${logFile}"
      exit "$status"
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
