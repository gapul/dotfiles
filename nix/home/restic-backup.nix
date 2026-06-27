{
  config,
  pkgs,
  lib,
  user,
  ...
}:
# restic による暗号化バックアップ + 整合性検証 + 実行監視を launchd で定期実行 (macOS 専用)。
# バックエンドは既存の rclone google-drive リモート ([[project_xdg_migration]] の rclone_conf)。
#
# 役割分担:
#   - system/app/config は nix+dotfiles で再現可能 (バックアップ不要)
#   - ここで守るのは「再現不可能なユーザーデータ」のみ
#
# 前提 (これが未了だと backup はスキップされるだけで無害):
#   1. rclone google-drive: の再認証 (`rclone authorize "drive"` → token を sops の rclone_conf へ)
#   2. リポジトリは初回成功時に自動 init される
#
# 注意 (循環依存): restic パスフレーズ・age鍵・ssh鍵は「この repo 自体の鍵」なので
#   restic では守らない。必ずパスワードマネージャ (Bitwarden/Ente) に別保管すること。
let
  home = config.home.homeDirectory;

  repository = "rclone:google-drive:restic-backup";
  rcloneConf = "${home}/.config/rclone/rclone.conf";
  passwordFile = config.sops.secrets."restic_password".path;
  logFile = "${home}/Library/Logs/restic-backup.log";

  # restic 環境 + macOS 通知シェル関数 (launchd の GUI セッションで osascript が使える)
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
    notify() { /usr/bin/osascript -e "display notification \"$2\" with title \"$1\"" 2>/dev/null || true; }
  '';

  # バックアップ対象 (再現不可能なユーザーデータのみ)
  backupPaths = [
    "${home}/Documents"
    "${home}/Pictures"
    "${home}/Downloads"
    "${home}/Movies"
    "${home}/Music"
  ];

  # 除外: 再生成可能 / 巨大 / DL一時物
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

    restic forget --prune \
      --keep-daily 7 --keep-weekly 4 --keep-monthly 6 || true

    echo "==================== $(date '+%Y-%m-%d %H:%M:%S') backup done (rc=$rc) ===================="
    exit $rc
  '';

  # 整合性検証 (週次)。破損を検知したら通知
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

  # 実行監視 (日次)。最後の成功スナップショットが古い/無いなら通知
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
    last_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$(echo "$latest" | cut -d. -f1)" +%s 2>/dev/null || echo 0)
    now=$(date +%s)
    age_days=$(( (now - last_epoch) / 86400 ))
    if [ "$age_days" -ge "$max_age_days" ]; then
      notify "restic ⚠️ バックアップが古い" "最後のバックアップは $age_days 日前です"
    fi
  '';

  # launchd agent 生成ヘルパ
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

  # restic パスフレーズ (sops の defaultSopsFile = secrets/secrets.yaml に格納済み)
  sops.secrets."restic_password".path = "${home}/.config/restic/password";

  launchd.agents = {
    # 日次 13:00 バックアップ
    restic-backup = agent "${backupScript}" [
      {
        Hour = 13;
        Minute = 0;
      }
    ];
    # 週次 (日) 14:00 整合性検証
    restic-check = agent "${checkScript}" [
      {
        Weekday = 0;
        Hour = 14;
        Minute = 0;
      }
    ];
    # 日次 19:00 実行監視
    restic-monitor = agent "${monitorScript}" [
      {
        Hour = 19;
        Minute = 0;
      }
    ];
  };
}
