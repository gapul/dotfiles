{
  config,
  pkgs,
  lib,
  ...
}:
# rclone で Google Drive (My Drive) を平文のまま ~/GoogleDrive にマウント (macOS 専用)。
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
# FUSE 実装は fuse-t (NFS バックエンド)。KEXT を使わないのでリカバリー/再起動不要。
#   FSKit バックエンド (macFUSE 5.2 / fuse-t 1.2) は 2026 時点で書き込みに難 (空き容量 0
#   報告で write 不可) があるため、read-write 共有には安定した NFS バックエンドを使う。
#   なお restic mount (アーカイブ閲覧) は bazil/fuse が macFUSE KEXT を直叩きするため
#   fuse-t では不可。閲覧は just archive-ls / archive-find で代替する。
#
# 前提 (未了ならマウントはスキップされるだけで無害):
#   1. fuse-t cask (tap: macos-fuse-t/cask)。KEXT 不要
#   2. rclone google-drive: が有効 (token 失効時は再認証)
let
  home = config.home.homeDirectory;

  remote = "google-drive:"; # My Drive ルート (平文)
  mountPoint = "${home}/GoogleDrive";
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
    exec rclone mount "${remote}" "${mountPoint}" \
      --config "${rcloneConf}" \
      -o backend=nfs \
      --exclude "/restic-backup/**" \
      --exclude "/restic-archive/**" \
      --vfs-cache-mode full \
      --vfs-cache-max-size 5G \
      --vfs-cache-max-age 168h \
      --dir-cache-time 72h \
      --poll-interval 1m \
      --volname "GoogleDrive" \
      --log-file "${logFile}" \
      --log-level INFO
  '';

  # マウント死活監視 (日次)。落ちていたら通知 (restic-monitor と同思想)
  monitorScript = pkgs.writeShellScript "rclone-gdrive-monitor" ''
    set -uo pipefail
    ${notify}
    if ! mount | grep -q " ${mountPoint} "; then
      notify "☁️ GoogleDrive 未マウント" "~/GoogleDrive が外れています。ログ: ${logFile}"
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
    # 常時マウント (落ちたら再マウント)
    rclone-gdrive = {
      enable = true;
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
    # 日次 19:30 死活監視 (restic-monitor 19:00 の後)
    rclone-gdrive-monitor = {
      enable = true;
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
