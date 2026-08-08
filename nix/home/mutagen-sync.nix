{
  config,
  pkgs,
  lib,
  ...
}:
# Two-way file sync with SSH-only hosts under ~/Sync via mutagen (macOS only).
# The purpose is handing files (video, build artifacts, one-off drops) to a machine we do not
# control well enough to run a resident daemon on. mutagen needs nothing pre-installed on the
# far side: it copies its own agent over SSH on first connect.
#
# Layout: everything replicated somewhere else lives under ~/Sync (see home/rclone-mount.nix).
#   ~/Sync/google-drive-*         <- rclone mount    (remote-primary, a mount)
#   ~/Sync/syncthing              <- Syncthing share (local-primary, real files)
#   ~/Sync/<ssh-host>             <- mutagen session (peer-primary, this file)
# The directory name is the SSH host name, and the directory on the far side is named after
# this Mac, so neither side can drift from what it is paired with.
#
# Why not Syncthing here: a Syncthing peer means a resident daemon and an open listener on the
# far side. That is fine for machines we own (homelab, macmini) and not fine for an external
# company server, so those go through mutagen over the SSH connection we already have.
#
# Why not restic-backed up: the data exists on both sides by definition, so restic keeps
# covering ~/Sync/syncthing only (see home/restic-backup.nix).
#
# Not for source code. Repositories are cloned on both sides with ghq and moved with git;
# .git carries absolute paths (git worktrees) and an index that must stay consistent with the
# working tree, neither of which survives being copied file by file.
#
# Prerequisites (harmless if unmet — the agent logs and exits, and launchd retries hourly):
#   the host resolves in ~/.ssh/config and accepts a key-based login. Check with
#     ssh <host> true
let
  home = config.home.homeDirectory;
  logDir = "${home}/Library/Logs/mutagen";

  # session name == directory name under ~/Sync == SSH host name.
  # remoteDir is relative to the far side's home directory.
  peers = [
    {
      host = "mvrx-nolang-dev";
      remoteDir = "Sync/MacBook-Mini";
    }
  ];

  # No openssh here on purpose: mutagen shells out to `ssh`, and the one that is known to work
  # with this machine's config (Bitwarden agent socket, per-host IdentityFile) is /usr/bin/ssh,
  # which launchd already has on PATH.
  mutagenBin = lib.makeBinPath [
    pkgs.mutagen
    pkgs.coreutils
  ];

  syncScript =
    {
      host,
      remoteDir,
    }:
    let
      localDir = "${home}/Sync/${host}";
      logFile = "${logDir}/${host}.log";
    in
    pkgs.writeShellScript "mutagen-sync-${host}" ''
      set -uo pipefail
      export PATH=${mutagenBin}:$PATH
      mkdir -p "${logDir}" "${localDir}"

      # Always exit 0. Paired with KeepAlive.SuccessfulExit=false below, launchd leaves a failed
      # attempt alone instead of respawning it in a tight loop; StartInterval retries it hourly,
      # which is what picks the session back up when the host was unreachable at login.
      if mutagen sync list "${host}" >/dev/null 2>&1; then
        exit 0
      fi

      echo "$(date '+%F %T') creating session ${host}" >>"${logFile}"
      # Creating a session contacts the far side to install the agent, so this is also where an
      # unreachable or unconfigured host shows up. mutagen keeps reconnecting on its own once
      # the session exists, so this only ever runs again after a terminate.
      if ! mutagen sync create \
        --name="${host}" \
        --ignore-vcs \
        --ignore=.DS_Store \
        "${localDir}" "${host}:${remoteDir}" >>"${logFile}" 2>&1; then
        echo "$(date '+%F %T') SKIP: could not create session (check: ssh ${host} true)" >>"${logFile}"
      fi
      exit 0
    '';
in
{
  home.packages = [ pkgs.mutagen ];

  # One agent per peer. The agent only ensures the session exists; the synchronization itself is
  # carried by mutagen's own daemon, which the CLI starts on demand and which stays resident.
  # If that daemon ever dies unnoticed, replace this with a foreground `mutagen daemon run` agent.
  launchd.agents = lib.listToAttrs (
    map (peer: {
      name = "mutagen-sync-${peer.host}";
      value = {
        enable = true;
        config = {
          ProgramArguments = [ "${syncScript peer}" ];
          RunAtLoad = true;
          StartInterval = 3600; # retry hourly: the host is often unreachable at login
          KeepAlive.SuccessfulExit = false;
          ProcessType = "Background";
          LowPriorityIO = true;
          Nice = 5;
          StandardErrorPath = "${logDir}/${peer.host}.log";
        };
      };
    }) peers
  );
}
