{
  config,
  pkgs,
  lib,
  user,
  ...
}:
# restic による暗号化バックアップを launchd で日次実行する (macOS 専用)。
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

  # バックアップ対象 (再現不可能なユーザーデータのみ)
  backupPaths = [
    "${home}/Documents"
    "${home}/Pictures/Design"
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
    **/from-downloads
    **/.git/objects
  '';

  backupScript = pkgs.writeShellScript "restic-backup" ''
    set -uo pipefail
    export PATH=${
      lib.makeBinPath [
        pkgs.restic
        pkgs.rclone
        pkgs.coreutils
      ]
    }:$PATH
    export RESTIC_REPOSITORY="${repository}"
    export RESTIC_PASSWORD_FILE="${passwordFile}"
    export RCLONE_CONFIG="${rcloneConf}"

    mkdir -p "$(dirname ${logFile})"
    exec >>"${logFile}" 2>&1
    echo "==================== $(date '+%Y-%m-%d %H:%M:%S') start ===================="

    # リモート未到達 (token 未再認証など) なら荒らさず skip
    if ! rclone about google-drive: >/dev/null 2>&1; then
      echo "SKIP: google-drive リモートに到達できません (rclone authorize 未了の可能性)"
      exit 0
    fi

    # 初回はリポジトリを自動 init
    if ! restic snapshots >/dev/null 2>&1; then
      echo "リポジトリが無いので init します"
      restic init || { echo "ERROR: restic init 失敗"; exit 1; }
    fi

    restic backup \
      --verbose=1 \
      --exclude-file=${excludeFile} \
      ${lib.concatStringsSep " " (map (p: "\"${p}\"") backupPaths)}
    rc=$?

    # 保持世代の整理
    restic forget --prune \
      --keep-daily 7 --keep-weekly 4 --keep-monthly 6 || true

    echo "==================== $(date '+%Y-%m-%d %H:%M:%S') done (rc=$rc) ===================="
    exit $rc
  '';
in
{
  home.packages = [ pkgs.restic ];

  # restic パスフレーズ (sops の defaultSopsFile = secrets/secrets.yaml に格納済み)
  sops.secrets."restic_password".path = "${home}/.config/restic/password";

  # 日次 13:00 (JST) に実行。スリープ中に時刻を跨いだら起床後に実行される。
  launchd.agents.restic-backup = {
    enable = true;
    config = {
      ProgramArguments = [ "${backupScript}" ];
      StartCalendarInterval = [
        {
          Hour = 13;
          Minute = 0;
        }
      ];
      RunAtLoad = false;
      ProcessType = "Background";
      LowPriorityIO = true;
      Nice = 5;
      StandardOutPath = "${home}/Library/Logs/restic-backup.launchd.out.log";
      StandardErrorPath = "${home}/Library/Logs/restic-backup.launchd.err.log";
    };
  };
}
