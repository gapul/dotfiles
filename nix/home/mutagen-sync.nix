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
# Which hosts get a session: whichever ones we actually ssh into, and only then. The zsh wrapper
# below pairs a host the first time we reach it, so the list maintains itself instead of being
# curated here, and ~/Sync never shows a directory for a machine we have not talked to.
# There is deliberately no launchd agent: a background job would recreate directories on a
# schedule, which is exactly the thing we do not want to see.
# The other half of that: a pairing that holds nothing on either side is retired on the next
# ssh, so ~/Sync lists the hosts we are exchanging files with rather than every host we have
# ever logged into. Emptiness is required on both sides, so retiring one cannot lose anything.
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
# Prerequisites (harmless if unmet — pairing is skipped and logged, and the next ssh retries):
#   the host accepts an unattended key-based login. Check with
#     ssh -o BatchMode=yes <host> true
#
# The "<host>-sync" convention: when ssh_config defines an entry of that name, it is dialled
# instead of the interactive one. That exists because an interactive entry can carry LocalForward
# plus ExitOnForwardFailure, and then every further connection exits 255 while a normal session
# holds those ports — precisely when the machine is in use. The sync alias clears forwardings.
# Agent access is not part of that convention any more: Host * pins IdentityAgent, which is what
# the mutagen daemon needs, since nothing hands SSH_AUTH_SOCK to it.
let
  home = config.home.homeDirectory;
  logDir = "${home}/Library/Logs/mutagen";

  # No openssh here on purpose: mutagen shells out to `ssh`, and the one that is known to work
  # with this machine's config (Bitwarden agent socket, per-host IdentityFile) is /usr/bin/ssh,
  # which launchd already has on PATH.
  mutagenBin = lib.makeBinPath [
    pkgs.mutagen
    pkgs.coreutils
  ];

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
    # after something that changes; *-sync is the alias we dial, not a machine of its own.
    case "$host" in
      *.* | *:* | */*) exit 0 ;;
      *-sync) exit 0 ;;
    esac
    case " github localhost " in *" $host "*) exit 0 ;; esac

    # Retire pairings that hold nothing. Without this every host we ever reached keeps a
    # directory in ~/Sync forever, which is the clutter the pairing rule was meant to avoid.
    # Only a pair that is empty on BOTH sides goes, so nothing can be lost by it, and only
    # after an hour of stillness, so a directory never disappears while it is being used.
    mutagen sync list --template \
      '{{range .}}{{.Name}} {{.Alpha.EndpointState.Files}} {{.Alpha.EndpointState.Directories}} {{.Beta.EndpointState.Files}} {{.Beta.EndpointState.Directories}} {{.Alpha.Path}}{{"\n"}}{{end}}' \
      2>/dev/null | while read -r name af ad bf bd path; do
      [ "$name" = "$host" ] && continue
      case "$path" in "${home}/Sync/"?*) ;; *) continue ;; esac
      # Directories is 1 for the synchronization root itself, so 1 still means empty.
      [ "$af" = 0 ] && [ "$bf" = 0 ] && [ "$ad" -le 1 ] && [ "$bd" -le 1 ] || continue
      [ -n "$(find "$path" -maxdepth 0 -mmin +60 2>/dev/null)" ] || continue
      echo "$(date '+%F %T') retiring empty pair $name"
      mutagen sync terminate "$name" >/dev/null 2>&1 || continue
      rmdir "$path" 2>/dev/null || true
      grep -lFx "$name" "$stateDir"/* 2>/dev/null | while read -r stale; do rm -f "$stale"; done
    done

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

    # Dial the sync alias when ssh_config defines one: the interactive entry may carry port
    # forwards that make a second connection fail exactly while the machine is in use.
    dial="$host"
    if awk -v want="$host-sync" '
      tolower($1)=="host"{for(i=2;i<=NF;i++) if($i==want){found=1}}
      END{exit !found}' "${home}/.ssh/config" 2>/dev/null; then
      dial="$host-sync"
    fi

    # Reachability and the parent directory in one round trip. BatchMode so a host that wants a
    # password fails here instead of waiting on a prompt that nobody can see.
    if ! /usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=10 "$dial" "mkdir -p '$remoteDir'"; then
      echo "$(date '+%F %T') skip $host: no unattended login"
      exit 0
    fi

    mkdir -p "$localDir"
    echo "$(date '+%F %T') creating session $host"
    if mutagen sync create \
      --name="$host" \
      --ignore-vcs \
      --ignore=.DS_Store \
      "$localDir" "$dial:$remoteDir"; then
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

  # mutagen defaults its data directory to ~/.mutagen, which is the last CLI in this config still
  # writing a dotfile into $HOME (adb is the other holdout, but android-tools 35.0.2 derives
  # $HOME/.android with no env override, so it stays). The directory holds the daemon's session
  # state, so it is data rather than config or cache.
  # The daemon inherits this from the shell that starts it: the ssh wrapper below is the only
  # thing that ever launches it, so there is no launchd agent needing the variable separately.
  home.sessionVariables.MUTAGEN_DATA_DIRECTORY = "${config.xdg.dataHome}/mutagen";

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

}
