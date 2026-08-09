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
# Which hosts get a session: whichever ones we actually ssh into. The zsh wrapper below pairs
# a host the first time we reach it, so the list maintains itself instead of being curated here.
# The peers list stays for the one host that needs a hand-written entry (see sshHost).
#
# Why not restic-backed up: the data exists on both sides by definition, so restic keeps
# covering ~/Sync/syncthing only (see home/restic-backup.nix). Nothing here is the only copy
# of anything — that is the price of not backing it up, and it is the rule for what we drop in.
#
# Why no failure notification, unlike restic: a stalled sync is noticed the moment a file does
# not show up on the other side, which is the only time this matters. `mutagen sync list` is the
# check. (If that stops being true, the pattern to copy is restic-backup.nix's ntfy notify().)
#
# Not for source code. Repositories are cloned on both sides with ghq and moved with git;
# .git carries absolute paths (git worktrees) and an index that must stay consistent with the
# working tree, neither of which survives being copied file by file.
#
# Prerequisites (harmless if unmet — the agent logs and exits, and launchd retries hourly):
#   the sshHost entry resolves in ~/.ssh/config and accepts a key-based login. Check with
#     ssh <sshHost> true
# That entry is a sync-only alias, and it has to be, for two reasons that both made this module
# fail silently for its first days:
#   - launchd does not hand SSH_AUTH_SOCK down, so an agent-held key is invisible here unless the
#     entry pins IdentityAgent itself.
#   - an interactive entry that carries LocalForward plus ExitOnForwardFailure makes every later
#     connection exit 255 while a normal session holds those ports. The alias clears forwardings.
# Both live in the sops-managed ssh_config, not here.
let
  home = config.home.homeDirectory;
  logDir = "${home}/Library/Logs/mutagen";

  # session name == directory name under ~/Sync == SSH host name.
  # remoteDir is relative to the far side's home directory.
  # sshHost is the entry mutagen dials, which is deliberately not the interactive one: see the
  # comment on the prerequisites above.
  peers = [
    {
      host = "mvrx-nolang-dev";
      sshHost = "mvrx-nolang-dev-sync";
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
      sshHost,
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
      # mutagen creates the synchronization root but not the directories above it, and a missing
      # parent only shows up afterwards as a transition problem on a session that otherwise looks
      # healthy ("unable to walk to transition root parent"). Make the parent first.
      /usr/bin/ssh -o BatchMode=yes "${sshHost}" "mkdir -p ${remoteDir}" >>"${logFile}" 2>&1 || true
      # Creating a session contacts the far side to install the agent, so this is also where an
      # unreachable or unconfigured host shows up. mutagen keeps reconnecting on its own once
      # the session exists, so this only ever runs again after a terminate.
      if ! mutagen sync create \
        --name="${host}" \
        --ignore-vcs \
        --ignore=.DS_Store \
        "${localDir}" "${sshHost}:${remoteDir}" >>"${logFile}" 2>&1; then
        echo "$(date '+%F %T') SKIP: could not create session (check: ssh ${sshHost} true)" >>"${logFile}"
      fi
      exit 0
    '';

  # Pair whatever host we just reached over ssh. Called by the zsh wrapper with the very argv
  # the user typed, so the destination has to be dug out of it the way ssh itself would.
  ensureScript = pkgs.writeShellScriptBin "mutagen-sync-ensure" ''
    set -uo pipefail
    export PATH=${mutagenBin}:$PATH

    stateDir="${home}/.local/state/mutagen-sync"
    mkdir -p "$stateDir" "${logDir}"
    # Nothing is ever printed to the caller: this runs behind an interactive ssh.
    exec >>"${logDir}/auto.log" 2>&1

    dest=""
    while [ $# -gt 0 ]; do
      case "$1" in
        # the short options that take a separate value
        -[bcDEeFIiJLlmOopQRSWw]) shift 2 || exit 0 ;;
        -*) shift ;;
        *) dest="$1"; break ;;
      esac
    done
    [ -n "$dest" ] || exit 0
    host="''${dest#*@}"

    # Only named entries pair. An address is a one-off, and it would name the sync directory
    # after something that changes; *-sync is our own alias for a host the peers list owns.
    case "$host" in
      *.* | *:* | */*) exit 0 ;;
      *-sync) exit 0 ;;
    esac
    case " github localhost " in *" $host "*) exit 0 ;; esac

    # Alias-proof identity: ssh -G resolves locally, so rpi4 / rpi / raspberrypi collapse into
    # one key and cannot end up as three sessions pointed at the same directory.
    key=$(/usr/bin/ssh -G "$host" 2>/dev/null | awk '
      $1=="hostname"{h=$2} $1=="user"{u=$2} $1=="port"{p=$2}
      END{if(h==""){exit 1}; s=u"_"h"_"p; gsub(/[^A-Za-z0-9_.-]/,"_",s); print s}')
    [ -n "$key" ] || exit 0
    marker="$stateDir/$key"
    if [ -f "$marker" ] && mutagen sync list "$(cat "$marker")" >/dev/null 2>&1; then
      exit 0
    fi
    if mutagen sync list "$host" >/dev/null 2>&1; then
      printf '%s' "$host" >"$marker"
      exit 0
    fi

    localDir="${home}/Sync/$host"
    remoteDir="Sync/$(scutil --get LocalHostName 2>/dev/null || hostname -s)"

    # Reachability and the parent directory in one round trip. BatchMode so a host that wants a
    # password fails here instead of waiting on a prompt that nobody can see.
    if ! /usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" "mkdir -p '$remoteDir'"; then
      echo "$(date '+%F %T') skip $host: no unattended login"
      exit 0
    fi

    mkdir -p "$localDir"
    echo "$(date '+%F %T') creating session $host"
    if mutagen sync create \
      --name="$host" \
      --ignore-vcs \
      --ignore=.DS_Store \
      "$localDir" "$host:$remoteDir"; then
      printf '%s' "$host" >"$marker"
    else
      # leave no empty ~/Sync/<host> behind to suggest a pairing that does not exist
      rmdir "$localDir" 2>/dev/null || true
    fi
    exit 0
  '';
in
{
  home.packages = [
    pkgs.mutagen
    ensureScript
  ];

  # Pair a host the first time we ssh into it. Deliberately after the session ends: during it a
  # second connection would ask the Bitwarden agent to approve again, and on a host carrying port
  # forwards it would fail outright. The wrapper never touches ssh's own behaviour or exit code.
  programs.zsh.initContent = lib.mkAfter ''
    function ssh() {
      command ssh "$@"
      local rc=$?
      (mutagen-sync-ensure "$@" &) >/dev/null 2>&1
      return $rc
    }
  '';

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
