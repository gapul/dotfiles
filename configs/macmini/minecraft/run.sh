#!/bin/bash
# マイクラのサーバーを1本起動する。どのインスタンスかは環境変数で渡る(hosts/macmini.nix の
# minecraftServers を参照)。ここに居る理由は「上がる前に世界を退避する」ため。
#
# バージョンを追う運用にした以上、ある朝いきなり新しい jar で起動する日が来る。ワールドの
# 変換は一方向なので、変換が始まる前のコピーを1つ残す。残すのは直前の1世代だけ。
set -u

SERVER_DIR="${SERVER_DIR:?SERVER_DIR が未設定}"
JAR="${SERVER_JAR:?SERVER_JAR が未設定}"
JAVA="${JAVA_BIN:?JAVA_BIN が未設定}"
MEM="${SERVER_MEM:-2G}"

cd "$SERVER_DIR" || exit 1

# nix store のパスは <hash>-paper-<version>-<build>.jar になるので、先頭は固定できない。
jar_version=$(basename "$JAR" | sed -nE 's/.*paper-([0-9][^-]*)-[0-9]+\.jar$/\1/p')

# Paper 26.2 で version_history.json が .paper/ 配下へ移った。両方見る。
running_version=""
for f in "$SERVER_DIR/.paper/version_history.json" "$SERVER_DIR/version_history.json"; do
  if [ -f "$f" ]; then
    running_version=$(sed -nE 's/.*"currentVersion":"[^"]*\(MC: ([^)]+)\)".*/\1/p' "$f")
    [ -n "$running_version" ] && break
  fi
done

if [ -n "$jar_version" ] && [ -n "$running_version" ] && [ "$jar_version" != "$running_version" ]; then
  snapshot="${SERVER_DIR%/}.pre-$running_version"
  rm -rf "$snapshot"
  mkdir -p "$snapshot"
  # 世界のフォルダ構成はバージョンで変わる(いまは world/ の中に dimensions/ が入る)。
  # 決め打ちせず、在るものだけ拾う。
  for d in world world_nether world_the_end; do
    [ -d "$d" ] && cp -a "$d" "$snapshot/"
  done
  cp -a server.properties "$snapshot/" 2>/dev/null
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $running_version -> $jar_version: 変換前の世界を $snapshot へ退避した"
fi

# 前段の lazymc が突然死ぬと、その下のサーバーが宙に浮いたまま残る。macOS では止まった状態
# (ps の T) で残るので TERM を送っても処理されず、世界のロックを掴んだままになる。次に起こした
# サーバーはそれで "already locked" で落ちる——遊ぼうとした側からは「起動しない」に見える。
# 掴んでいるプロセスが居たら先に片付ける。誰も繋がっていないから落として困る人は居ない。
stale=$(/usr/sbin/lsof -t "$SERVER_DIR/world/session.lock" 2>/dev/null)
if [ -n "$stale" ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] 旧サーバー ($stale) が世界を掴んでいるので落とす"
  # 止まっている相手には CONT を先に送る。そうしないと TERM が配送されるだけで処理されない。
  # shellcheck disable=SC2086  # 複数 pid をそのまま渡したい
  kill -CONT $stale 2>/dev/null
  # shellcheck disable=SC2086
  kill -TERM $stale 2>/dev/null
  for _ in $(seq 1 30); do
    # shellcheck disable=SC2086
    kill -0 $stale 2>/dev/null || break
    sleep 1
  done
  # shellcheck disable=SC2086
  kill -KILL $stale 2>/dev/null
fi

# 宣言された jar は store への symlink として置き直す。前回の分(= symlink)は毎回消すので、
# 宣言から外した jar は次の起動で居なくなる。手で入れた実体の jar には触らない。
# Paper は plugins/、Fabric は mods/ を読む。どちらか片方しか使わないので、宣言も置き場所も
# 無いなら作らない(Paper のディレクトリに空の mods/ を生やさないため)。
link_jars() {
  dir=$1
  shift
  [ -n "$*" ] || [ -d "$dir" ] || return 0
  mkdir -p "$dir"
  find "$dir" -maxdepth 1 -type l -name '*.jar' -delete
  for jar in "$@"; do
    name=$(basename "$jar")
    # store の名前は <hash>-<本来の名前>.jar。hash に - は入らないので先頭だけ落とせばいい。
    ln -sfn "$jar" "$dir/${name#*-}"
  done
}
# shellcheck disable=SC2086  # 空白区切りの一覧をそのまま引数として渡したい
link_jars plugins ${PLUGINS:-}
# shellcheck disable=SC2086
link_jars mods ${MODS:-}

# Aikar's flags から AlwaysPreTouch を外し -Xms を小さくしてある。無人時間が長く、24GB を
# AI スタックと分け合う機械では、起動時に全ヒープを commit するのは損なので。
exec "$JAVA" \
  -Xms512M "-Xmx$MEM" \
  -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 \
  -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC \
  -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M \
  -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 \
  -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 \
  -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 \
  -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1 \
  -jar "$JAR" --nogui
