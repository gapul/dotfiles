#!/bin/bash
# ワールドの日次バックアップ。Realms が当たり前にやっている「壊しても戻せる」を用意する。
#
# 生きたままコピーすると書き込み途中のリージョンを掴みうるので、いったん止めてから固める。
# Paper は SIGTERM でワールドを保存して終了するので、bootout → コピー → bootstrap が確実。
# KeepAlive が効いているため、単に kill すると即座に上がってきてしまう。停止は4秒弱 +
# コピー時間で、走らせるのは朝4時40分(restic の 5:00 より前。同じ晩のうちに offsite へ乗る)。
set -u

LABEL=org.nixos.minecraft
PLIST=/Library/LaunchDaemons/$LABEL.plist
SERVER=/Users/mcsrv/server
DEST=/Users/Shared/minecraft-backups
KEEP=7

start_again() {
  # 途中で何が起きてもサーバーは戻す。既に動いていれば bootstrap が失敗するだけで無害。
  /bin/launchctl bootstrap system "$PLIST" 2>/dev/null || true
}
trap start_again EXIT

mkdir -p "$DEST"
chmod 755 "$DEST"

/bin/launchctl bootout "system/$LABEL" 2>/dev/null
# bootout は即座には終わらないので、プロセスが消えるまで待つ(最大30秒)。
for _ in $(seq 30); do
  pgrep -f "paper-.*\.jar" >/dev/null 2>&1 || break
  sleep 1
done

stamp=$(date '+%Y%m%d-%H%M')
out="$DEST/world-$stamp.tar.gz"
if /usr/bin/tar czf "$out" -C "$SERVER" world world_nether world_the_end server.properties whitelist.json ops.json 2>/dev/null; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $(basename "$out") $(du -h "$out" | cut -f1)"
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] バックアップに失敗した" >&2
  rm -f "$out"
fi

# 世代を絞る。offsite は restic が /Users/Shared/minecraft-backups ごと持っていく。
# shellcheck disable=SC2012  # 名前は自分で付けた world-YYYYmmdd-HHMM.tar.gz なので ls で足りる
ls -1t "$DEST"/world-*.tar.gz 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r old; do
  rm -f "$old"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] 古い世代を削除: $(basename "$old")"
done
