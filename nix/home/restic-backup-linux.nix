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

  inherit (common) repository;
  inherit (common) rcloneConf;
  passwordFile = config.sops.secrets."restic_password".path;
  logFile = "${home}/.local/state/restic/restic-backup.log";

  resticEnv = ''
    export PATH=${
      lib.makeBinPath [
        pkgs.restic
        pkgs.rclone
        pkgs.coreutils
        pkgs.jq
        pkgs.libnotify
      ]
    }:$PATH
    export RESTIC_REPOSITORY="${repository}"
    export RESTIC_PASSWORD_FILE="${passwordFile}"
    export RCLONE_CONFIG="${rcloneConf}"
    notify() { notify-send "$1" "$2" 2>/dev/null || true; }
  '';

  # Backup targets (only non-reproducible user data). Linux XDG directories.
  backupPaths = [
    "${home}/Documents"
    "${home}/Pictures"
    "${home}/Downloads"
    "${home}/Music"
    "${home}/Videos"
  ];

  excludeFile = pkgs.writeText "restic-excludes" ''
    **/node_modules
    **/.direnv
    **/.venv
    **/target
    **/dist
    **/build
    **/.next
    **/.expo
    **/.git/objects
  '';

  backupScript = pkgs.writeShellScript "restic-backup" ''
    set -uo pipefail
    ${resticEnv}
    mkdir -p "$(dirname ${logFile})"
    exec >>"${logFile}" 2>&1
    echo "==================== $(date '+%Y-%m-%d %H:%M:%S') backup start ===================="

    if ! rclone about google-drive: >/dev/null 2>&1; then
      echo "SKIP: google-drive リモートに到達できません (rclone authorize 未了の可能性)"
      exit 0
    fi

    if ! restic snapshots >/dev/null 2>&1; then
      echo "リポジトリが無いので init します"
      restic init || { echo "ERROR: restic init 失敗"; exit 1; }
    fi

    restic backup \
      --verbose=1 \
      --exclude-file=${excludeFile} \
      ${lib.concatStringsSep " " (map (p: "\"${p}\"") backupPaths)}
    rc=$?

    ${common.forgetInvocation}

    echo "==================== $(date '+%Y-%m-%d %H:%M:%S') backup done (rc=$rc) ===================="
    exit $rc
  '';

  checkScript = pkgs.writeShellScript "restic-check" ''
    set -uo pipefail
    ${resticEnv}
    exec >>"${logFile}" 2>&1
    echo "-------------------- $(date '+%Y-%m-%d %H:%M:%S') check start --------------------"
    if ! rclone about google-drive: >/dev/null 2>&1; then
      echo "SKIP: リモート未到達"; exit 0
    fi
    if restic check; then
      echo "check OK"
    else
      echo "check FAILED"
      notify "restic ⚠️ リポジトリ破損の疑い" "restic check 失敗。ログを確認してください"
    fi
  '';

  monitorScript = pkgs.writeShellScript "restic-monitor" ''
    set -uo pipefail
    ${resticEnv}
    max_age_days=2

    if ! rclone about google-drive: >/dev/null 2>&1; then
      notify "restic ⚠️ バックアップ未稼働" "google-drive 未認証。rclone authorize drive を実行してください"
      exit 0
    fi
    latest=$(restic snapshots --latest 1 --json 2>/dev/null | jq -r '.[0].time // empty')
    if [ -z "$latest" ]; then
      notify "restic ⚠️ スナップショット無し" "まだ一度もバックアップされていません"
      exit 0
    fi
    # GNU date: can parse ISO8601 directly
    last_epoch=$(date -d "$latest" +%s 2>/dev/null || echo 0)
    now=$(date +%s)
    age_days=$(( (now - last_epoch) / 86400 ))
    if [ "$age_days" -ge "$max_age_days" ]; then
      notify "restic ⚠️ バックアップが古い" "最後のバックアップは $age_days 日前です"
    fi
  '';

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
    restic-backup = mkService "restic 暗号化バックアップ" backupScript;
    restic-check = mkService "restic 整合性検証" checkScript;
    restic-monitor = mkService "restic 実行監視" monitorScript;
  };
  systemd.user.timers = {
    restic-backup = mkTimer "日次 restic バックアップ" "*-*-* 13:00:00";
    restic-check = mkTimer "週次 restic 整合性検証" "Sun *-*-* 14:00:00";
    restic-monitor = mkTimer "日次 restic 実行監視" "*-*-* 19:00:00";
  };
}
