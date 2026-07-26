# restic バックアップの単一情報源 (SSO)。
#
# darwin 版 (home/restic-backup.nix, launchd) と linux 版 (home/restic-backup-linux.nix,
# systemd) と Justfile のバックアップ系レシピが、ここから同じ値を引く。
#
# 重要: repository / forget 保持ポリシー / archive タグは「共有 restic リポジトリ」
#   (Mac と pve が同一リポを共有 — restic shared repo) を壊さないため、必ず全ホストで
#   一致させること。ここが唯一の定義点なので、変更すれば両ホスト + Justfile が追従する。
{ home }:
rec {
  repository = "rclone:google-drive:restic-backup";
  rcloneConf = "${home}/.config/rclone/rclone.conf";
  passwordFile = "${home}/.config/restic/password";

  # cold アーカイブの目印タグ。just archive が --tag で付与し、forget が --keep-tag で保持する。
  # 付与側 (Justfile) と保持側 (下の forgetInvocation) がずれると cold が warm 扱いで消える。
  archiveTag = "archive";

  # forget 保持ポリシー呼び出し (両ホストの backupScript が共有)。
  #   --keep-tag archive: cold アーカイブは永久保持。warm (無タグ) のみ間引く。
  # 注意: この文字列のインデント/改行は生成スクリプトのバイト列に直接入る。
  #   両 backupScript は 4 スペースインデントの位置でこれを展開する前提。
  forgetInvocation = ''
    restic forget --prune \
      --keep-tag ${archiveTag} \
      --keep-daily 7 --keep-weekly 4 --keep-monthly 6 || true'';

  # Justfile / 対話シェル用に同じ値を吐く env ファイルの中身。
  #   home-manager が ~/.config/restic/env に配置し、Justfile の restic_env が source する。
  envFileText = ''
    # 自動生成 (nix/lib/restic-common.nix)。手で編集しない。
    export RESTIC_REPOSITORY="${repository}"
    export RESTIC_PASSWORD_FILE="${passwordFile}"
    export RCLONE_CONFIG="${rcloneConf}"
    export RESTIC_ARCHIVE_TAG="${archiveTag}"
  '';
}
