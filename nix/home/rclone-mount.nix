{
  config,
  pkgs,
  lib,
  ...
}:
# rclone で暗号化アーカイブ (crypt remote) を ~/Archive に常時マウント (macOS 専用)。
# ストレージ階層の cold 層: 「使わなくなったがローカルから消したいデータ」をオンライン保管し、
# ローカル SSD を消費せず Finder/CLI から透過的に閲覧・編集する。
#
# 階層の役割分担:
#   - GitHub          : 再現可能なコード (hot)
#   - restic→GDrive   : 再現不可能な現役ファイル (warm, 暗号化・世代管理) … restic-backup.nix
#   - rclone mount    : 使わなくなったアーカイブ (cold, 暗号化)              … このファイル
#
# 重要 (restic との衝突回避):
#   マウント先 ~/Archive は restic の backupPaths (Documents/Pictures/Downloads/Movies/Music) の
#   *外* に置く。配下に置くと restic がマウントを再帰スキャンし、GDrive 上の全アーカイブを
#   VFS 経由で DL → バックアップしようとして容量・転送量が爆発する。
#
# 前提 (未了ならマウントはスキップされるだけで無害):
#   1. macfuse cask がインストール済み (KEXT 承認 + 再起動が必要)
#   2. rclone google-drive: の再認証 (token 失効時)
#   3. crypt remote [archive] が rclone.conf にある (sops の rclone_conf に格納済み)
#
# 注意 (循環依存): crypt パスフレーズは sops 内の rclone.conf に obscured で入っている。
#   sops age 鍵ごと失うと復号不能なので、plaintext を Bitwarden に別保管すること。
let
  home = config.home.homeDirectory;

  remote = "archive:"; # crypt remote (rclone.conf 内、実体は google-drive:archive)
  mountPoint = "${home}/Archive";
  rcloneConf = "${home}/.config/rclone/rclone.conf";
  cacheDir = "${home}/.cache/rclone";
  logFile = "${home}/Library/Logs/rclone-archive.log";

  rcloneBin = lib.makeBinPath [
    pkgs.rclone
    pkgs.coreutils
  ];

  # macFUSE のマウントヘルパは /usr/local/bin or /Library にあるため PATH に追加。
  mountScript = pkgs.writeShellScript "rclone-archive-mount" ''
    set -uo pipefail
    export PATH=${rcloneBin}:/usr/local/bin:/Library/Filesystems/macfuse.fs/Contents/Resources:$PATH
    mkdir -p "$(dirname ${logFile})" "${cacheDir}" "${mountPoint}"

    # rclone.conf がまだ無い (sops 未 deploy) なら起動しない
    if [ ! -f "${rcloneConf}" ]; then
      echo "$(date '+%F %T') SKIP: ${rcloneConf} が無い (sops 未 deploy)" >>"${logFile}"
      exit 0
    fi

    # 既にマウント済みなら何もしない (launchd 再投入対策)
    if mount | grep -q " ${mountPoint} "; then
      echo "$(date '+%F %T') already mounted" >>"${logFile}"
      exit 0
    fi

    echo "$(date '+%F %T') mount start" >>"${logFile}"
    # foreground 実行 (launchd が KeepAlive で管理。--daemon は使わない)
    exec rclone mount "${remote}" "${mountPoint}" \
      --config "${rcloneConf}" \
      --vfs-cache-mode full \
      --vfs-cache-max-size 5G \
      --vfs-cache-max-age 168h \
      --dir-cache-time 72h \
      --poll-interval 1m \
      --volname "Archive" \
      --no-modtime \
      --log-file "${logFile}" \
      --log-level INFO
  '';
in
{
  home.packages = [ pkgs.rclone ];

  launchd.agents.rclone-archive = {
    enable = true;
    config = {
      ProgramArguments = [ "${mountScript}" ];
      RunAtLoad = true;
      KeepAlive = true; # 落ちたら再マウント
      ProcessType = "Background";
      LowPriorityIO = true;
      Nice = 5;
      StandardErrorPath = "${logFile}";
    };
  };
}
