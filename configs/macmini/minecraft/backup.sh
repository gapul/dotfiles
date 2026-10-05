#!/bin/bash
# 全インスタンスのワールドを日次でバックアップする。Realms から移ってくる以上、
# 「壊しても戻せる」は要る。対象は BACKUP_TARGETS に "ラベル:ディレクトリ" の形で並ぶ。
#
# 生きたままコピーすると書き込み途中のリージョンを掴みうるので、1本ずつ止めて写す。
# Paper は SIGTERM でワールドを保存して終了する。KeepAlive が効いているため単に kill すると
# 即復帰してしまうので bootout → コピー → bootstrap にし、trap で必ず戻す。
# 走らせるのは 4:40(restic の 5:00 より前。同じ晩のうちに offsite へ乗る)。
set -u

TARGETS="${BACKUP_TARGETS:?BACKUP_TARGETS が未設定}"
DEST=/Users/Shared/minecraft-backups
KEEP=7

mkdir -p "$DEST"
chmod 755 "$DEST"

current_label=""
start_again() {
  [ -n "$current_label" ] || return 0
  /bin/launchctl bootstrap system "/Library/LaunchDaemons/$current_label.plist" 2>/dev/null || true
}
trap start_again EXIT

for target in $TARGETS; do
  name="${target%%:*}"
  dir="${target#*:}"
  [ -d "$dir" ] || { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $name: $dir が無いので飛ばす"; continue; }

  current_label="org.nixos.minecraft-$name"
  /bin/launchctl bootout "system/$current_label" 2>/dev/null
  for _ in $(seq 30); do
    pgrep -f "SERVER_DIR=$dir" >/dev/null 2>&1 || pgrep -f "$dir" >/dev/null 2>&1 || break
    sleep 1
  done

  # 世界のフォルダ構成はバージョンで変わる(いまは world/ の中に dimensions/ がある)。
  # 決め打ちすると tar がこけてバックアップが丸ごと空振りするので、在るものだけ渡す。
  #
  # mods/ と plugins/ も拾う。宣言してある jar は store への symlink なので中身は入らない
  # (復元は rebuild 側の仕事)が、試しに手で放り込んだ実体の jar はここにしか無い。
  # config/ と defaultconfigs/ は mod ごとの設定で、これも生成物ではなく蓄積物。
  # 世代は tar.gz ではなく <name>/<日時>/ のディレクトリで持つ。前の世代を APFS クローン
  # (cp -c)で複製してから rsync で差分だけ差し替えるので、変わっていないリージョンは世代間で
  # ブロックを共有する。tar.gz だと 7 世代 = 世界 7 個ぶんだったのが、世界 1 個 + 1 週間の変更で
  # 済む。restic もファイル単位なら重複排除が効くので、offsite に毎晩世界まるごとを積まなくなる。
  # ハードリンク(--link-dest)にしないのは、戻した先で書き換えたときに他の世代まで変わるから。
  snap_dir="$DEST/$name"
  snap="$snap_dir/$(date '+%Y%m%d-%H%M')"
  work="$snap_dir/.partial"
  mkdir -p "$snap_dir"
  rm -rf "$work"
  # shellcheck disable=SC2012  # 名前は自分で付けた YYYYmmdd-HHMM なので ls で足りる
  prev=$(ls -1d "$snap_dir"/2* 2>/dev/null | tail -n 1)
  if [ -n "$prev" ]; then
    /bin/cp -cpR "$prev" "$work"
  else
    mkdir -p "$work"
  fi

  sources=()
  for f in world world_nether world_the_end mods plugins config defaultconfigs \
    server.properties whitelist.json ops.json banned-players.json; do
    if [ -e "$dir/$f" ]; then
      sources+=("$dir/$f")
    else
      # 前の世代から引き継いだものが元から消えていたら、こちらからも消す。
      rm -rf "${work:?}/$f"
    fi
  done
  if [ ${#sources[@]} -eq 0 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $name: 固めるものが無い" >&2
    rm -rf "$work"
  elif /usr/bin/rsync -a --delete "${sources[@]}" "$work/"; then
    # サーバーのファイルは mcsrv の 600 が混じる。restic は gapul で読むので読めるようにしておく
    # (tar.gz のころも root の 644 で置いていたので、見える範囲は変わらない)。
    chmod -R a+rX "$work"
    mv "$work" "$snap"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $name: $(basename "$snap")"
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $name: バックアップに失敗した" >&2
    rm -rf "$work"
  fi

  start_again
  current_label=""

  # 世代を絞る。offsite は restic が /Users/Shared/minecraft-backups ごと持っていく。
  # shellcheck disable=SC2012
  ls -1d "$snap_dir"/2* 2>/dev/null | sort -r | tail -n +$((KEEP + 1)) | while read -r old; do
    rm -rf "$old"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $name: 古い世代を削除 $(basename "$old")"
  done
done
