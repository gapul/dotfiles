{
  config,
  pkgs,
  lib,
  ...
}:
# Encrypted backup + integrity check + run monitoring via restic, scheduled by launchd (macOS only).
# Backend is the existing rclone google-drive remote (rclone_conf from [[project_xdg_migration]]).
#
# Division of responsibility:
#   - system/app/config are reproducible via nix+dotfiles (no backup needed)
#   - what we protect here is only the "non-reproducible user data"
#
# Prerequisites (if unmet, backup just skips harmlessly):
#   1. Re-auth rclone google-drive: (`rclone authorize "drive"` → put the token into sops's rclone_conf)
#   2. The repository is auto-init'd on the first success
#
# Note (circular dependency): the restic passphrase, age key, and ssh key are "the keys to this repo itself",
#   so they're not protected by restic. Always store them separately in a password manager (Bitwarden/Ente).
let
  home = config.home.homeDirectory;

  # SSO: repository / retention policy / archive tag / rclone conf live in nix/lib/restic-common.nix.
  #   The linux version (restic-backup-linux.nix) and the Justfile pull the same values. To avoid breaking the shared repo.
  common = import ../lib/restic-common.nix { inherit home; };

  inherit (common) repository;
  inherit (common) rcloneConf;
  passwordFile = config.sops.secrets."restic_password".path;
  logFile = "${home}/Library/Logs/restic-backup.log";

  # ntfy failure notification (homelab's ntfy.gapul.net). The URL (topic included) and token are sops-managed.
  #   If they're unexpanded/unreadable, notify quietly falls back to osascript only.
  ntfyUrlFile = config.sops.secrets."unified_calendar/ntfy_url".path;
  ntfyTokenFile = config.sops.secrets."unified_calendar/ntfy_token".path;

  # restic env + macOS notification shell function (osascript works in launchd's GUI session)
  resticEnv = ''
    export PATH=${
      lib.makeBinPath [
        pkgs.restic
        pkgs.rclone
        pkgs.coreutils
        pkgs.jq
      ]
    }:$PATH
    export RESTIC_REPOSITORY="${repository}"
    export RESTIC_PASSWORD_FILE="${passwordFile}"
    export RCLONE_CONFIG="${rcloneConf}"
    # macOS notification (GUI session) + ntfy push (immediate phone alert). The main process continues even if either fails.
    notify() {
      /usr/bin/osascript -e "display notification \"$2\" with title \"$1\"" 2>/dev/null || true
      if [ -r "${ntfyUrlFile}" ] && [ -r "${ntfyTokenFile}" ]; then
        /usr/bin/curl -fsS --max-time 15 \
          -H "Authorization: Bearer $(cat "${ntfyTokenFile}")" \
          -H "Title: restic (mac)" \
          -H "Priority: high" \
          -H "Tags: warning" \
          -d "$1: $2" \
          "$(cat "${ntfyUrlFile}")" >/dev/null 2>&1 || true
      fi
    }
  '';

  # Backup targets (non-reproducible user data only)
  backupPaths = [
    "${home}/Documents"
    "${home}/Pictures"
    "${home}/Downloads"
    "${home}/Movies"
    "${home}/Music"
    # Only the Syncthing share, never ~/Sync itself: its siblings are rclone mounts of Google Drive,
    # and the restic repository lives on that same Drive, so backing up the mount would feed the
    # repository into itself.
    "${home}/Sync/syncthing" # Syncthing share (local-primary replicated data)
    "${home}/Library/Application Support/minecraft/saves" # Minecraft worlds (non-reproducible)
  ];

  # Exclude: regenerable / huge / DL temp files
  excludeFile = pkgs.writeText "restic-excludes" ''
    **/node_modules
    **/.direnv
    **/.venv
    **/target
    **/dist
    **/build
    **/.next
    **/.expo
    **/.DS_Store
    **/*.photoslibrary
    **/.git/objects
    **/ae-mcp-commands
  '';

  backupScript = pkgs.writeShellScript "restic-backup" ''
    set -uo pipefail
    ${resticEnv}
    mkdir -p "$(dirname ${logFile})"
    exec >>"${logFile}" 2>&1
    echo "==================== $(date '+%Y-%m-%d %H:%M:%S') backup start ===================="

    if ! rclone about google-drive: >/dev/null 2>&1; then
      echo "SKIP: cannot reach the google-drive remote (rclone authorize may be incomplete)"
      exit 0
    fi

    if ! restic snapshots >/dev/null 2>&1; then
      echo "repository not found, running init"
      restic init || { echo "ERROR: restic init failed"; exit 1; }
    fi

    restic backup \
      --verbose=1 \
      --exclude-file=${excludeFile} \
      ${lib.concatStringsSep " " (map (p: "\"${p}\"") backupPaths)}
    rc=$?

    # --keep-tag archive: exclude cold archives (tagged via just archive with --tag archive) from
    #   the keep policy and retain them forever. Prune only warm (untagged) ones.
    #   (restic also refuses to delete the last snapshot in each group, so double protection)
    ${common.forgetInvocation}

    echo "==================== $(date '+%Y-%m-%d %H:%M:%S') backup done (rc=$rc) ===================="
    if [ "$rc" -ne 0 ]; then
      notify "restic ⚠️ backup failed" "restic backup failed with rc=$rc. Please check the log: ${logFile}"
    fi
    exit $rc
  '';

  # Integrity check (weekly). Notify if corruption is detected
  checkScript = pkgs.writeShellScript "restic-check" ''
    set -uo pipefail
    ${resticEnv}
    exec >>"${logFile}" 2>&1
    echo "-------------------- $(date '+%Y-%m-%d %H:%M:%S') check start --------------------"
    if ! rclone about google-drive: >/dev/null 2>&1; then
      echo "SKIP: remote unreachable"; exit 0
    fi
    if restic check; then
      echo "check OK"
    else
      echo "check FAILED"
      notify "restic ⚠️ possible repository corruption" "restic check failed. Please check the log"
    fi
  '';

  # Run monitoring (daily). Notify if the last successful snapshot is old/missing
  monitorScript = pkgs.writeShellScript "restic-monitor" ''
    set -uo pipefail
    ${resticEnv}
    max_age_days=2

    if ! rclone about google-drive: >/dev/null 2>&1; then
      notify "restic ⚠️ backup not running" "google-drive not authenticated. Please run rclone authorize drive"
      exit 0
    fi
    latest=$(restic snapshots --latest 1 --json 2>/dev/null | jq -r '.[0].time // empty')
    if [ -z "$latest" ]; then
      notify "restic ⚠️ no snapshots" "no backup has been made yet"
      exit 0
    fi
    last_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$(echo "$latest" | cut -d. -f1)" +%s 2>/dev/null || echo 0)
    now=$(date +%s)
    age_days=$(( (now - last_epoch) / 86400 ))
    if [ "$age_days" -ge "$max_age_days" ]; then
      notify "restic ⚠️ backup is stale" "the last backup was $age_days days ago"
    fi
  '';

  # launchd agent generation helper
  agent = program: schedule: {
    enable = true;
    config = {
      ProgramArguments = [ program ];
      StartCalendarInterval = schedule;
      RunAtLoad = false;
      ProcessType = "Background";
      LowPriorityIO = true;
      Nice = 5;
    };
  };
in
{
  home.packages = [ pkgs.restic ];

  # restic passphrase (stored in sops's defaultSopsFile = secrets/secrets.yaml)
  sops.secrets."restic_password".path = common.passwordFile;

  # env sourced by the Justfile / interactive shell (SSO for repo/password/rclone/archiveTag).
  home.file.".config/restic/env".text = common.envFileText;

  # For ntfy failure notifications (URL is a publish endpoint including the topic, token is a Bearer tk_...).
  #   Even if unset, notify still works with osascript only, so it's harmless.
  sops.secrets."unified_calendar/ntfy_url".path = "${home}/.config/ntfy/url";
  sops.secrets."unified_calendar/ntfy_token".path = "${home}/.config/ntfy/token";

  launchd.agents = {
    # daily 13:00 backup
    restic-backup = agent "${backupScript}" [
      {
        Hour = 13;
        Minute = 0;
      }
    ];
    # weekly (Sun) 14:00 integrity check
    restic-check = agent "${checkScript}" [
      {
        Weekday = 0;
        Hour = 14;
        Minute = 0;
      }
    ];
    # daily 19:00 run monitoring
    restic-monitor = agent "${monitorScript}" [
      {
        Hour = 19;
        Minute = 0;
      }
    ];
  };
}
