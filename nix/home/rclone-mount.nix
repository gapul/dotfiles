{
  config,
  pkgs,
  lib,
  ...
}:
# rclone で Google Drive (My Drive) を平文のまま ~/Cloud/GoogleDrive にマウント (macOS 専用)。
# 用途は cold アーカイブではなく「他者との共有・連携」。暗号化しないのは Web UI や
# 共有相手から普通に見えてほしいため。
#
# ストレージ階層での位置づけ:
#   - GitHub                      : 再現可能なコード
#   - restic (warm, 無タグ)        : 再現不可能な現役ファイル … restic-backup.nix
#   - restic (cold, --tag archive) : 使わなくなったファイル (永久保持) … restic-backup.nix + just archive
#   - rclone mount (このファイル)   : 他者と共有する平文クラウドフォルダ
#
# 重要 (restic リポジトリの保護):
#   My Drive 直下には restic-backup/ (warm+cold の暗号化リポジトリ) が同居する。
#   read-write マウントから誤って削除されると致命的なので、マウントの可視範囲から
#   除外 (--exclude) する。除外パスはマウント上に現れず、削除もできない。
#
# マウント方式は rclone nfsmount (rclone 内蔵 NFS サーバ + macOS 標準 NFS クライアント)。
#   FUSE/KEXT/fuse-t を一切使わない完全 FOSS 方式。プロプライエタリな fuse-t 依存を排除。
#   注意 (NFS 方式の癖): atime/mtime を個別に設定できず、Finder 閲覧で mtime が更新され
#   rclone が丸ごと再アップロードすることがある。--read-only 時の書き込みは無警告で失敗。
#   なお restic mount (アーカイブ閲覧) は bazil/fuse が macFUSE KEXT を直叩きするため
#   この方式では不可。閲覧は just archive-ls / archive-find で代替する。
#
# 前提 (未了ならマウントはスキップされるだけで無害):
#   1. rclone google-drive: が有効 (token 失効時は再認証)。追加ソフト/KEXT 不要
let
  home = config.home.homeDirectory;

  remote = "google-drive:"; # My Drive ルート (平文)
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
      echo "$(date '+%F %T') SKIP: ${rcloneConf} が無い (sops 未 deploy)" >>"${logFile}"
      exit 0
    fi
    if mount | grep -q " ${mountPoint} "; then
      echo "$(date '+%F %T') already mounted" >>"${logFile}"
      exit 0
    fi

    echo "$(date '+%F %T') mount start" >>"${logFile}"
    # foreground 実行 (launchd が KeepAlive で管理)。restic リポジトリは除外して保護。
    # rclone nfsmount: rclone 内蔵 NFS サーバ + macOS 標準 NFS クライアントでマウントし、
    # FUSE/KEXT/fuse-t を一切使わない (完全 FOSS)。fuse-t 固有の -o/--volname は不要。
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

  # マウント死活監視 (日次)。落ちていたら通知 (restic-monitor と同思想)
  monitorScript = pkgs.writeShellScript "rclone-gdrive-monitor" ''
    set -uo pipefail
    ${notify}
    if ! mount | grep -q " ${mountPoint} "; then
      notify "☁️ GoogleDrive 未マウント" "~/Cloud/GoogleDrive が外れています。ログ: ${logFile}"
      exit 0
    fi
    # マウントはされているが読めない (stale) ケースも検知
    if ! /bin/ls "${mountPoint}" >/dev/null 2>&1; then
      notify "☁️ GoogleDrive 応答なし" "マウントは在るが読めません (stale の可能性)"
    fi
  '';
in
{
  home.packages = [ pkgs.rclone ];

  launchd.agents = {
    # 旧 ~/Cloud/GoogleDrive マウントは廃止。
    # 現在は手動管理の LaunchAgent で personal/school を別々にマウントする:
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
    # 旧 ~/Cloud/GoogleDrive の死活監視も廃止。
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
