#!/bin/bash
# 全インスタンスのワールドを日次でバックアップする。Realms から移ってくる以上、
# 「壊しても戻せる」は要る。対象は BACKUP_TARGETS に "ラベル:ディレクトリ" の形で並ぶ。
#
# 生きたままコピーすると書き込み途中のリージョンを掴みうるので、1本ずつ止めて固める。
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
  items=()
  for f in world world_nether world_the_end mods plugins config defaultconfigs \
    server.properties whitelist.json ops.json banned-players.json; do
    [ -e "$dir/$f" ] && items+=("$f")
  done
  if [ ${#items[@]} -eq 0 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $name: 固めるものが無い" >&2
  else
    out="$DEST/$name-$(date '+%Y%m%d-%H%M').tar.gz"
    if /usr/bin/tar czf "$out" -C "$dir" "${items[@]}"; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] $name: $(basename "$out") $(du -h "$out" | cut -f1)"
    else
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] $name: バックアップに失敗した" >&2
      rm -f "$out"
    fi
  fi

  start_again
  current_label=""

  # 世代を絞る。offsite は restic が /Users/Shared/minecraft-backups ごと持っていく。
  # shellcheck disable=SC2012  # 名前は自分で付けた <name>-YYYYmmdd-HHMM.tar.gz なので ls で足りる
  ls -1t "$DEST/$name"-*.tar.gz 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r old; do
    rm -f "$old"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $name: 古い世代を削除 $(basename "$old")"
  done
done
