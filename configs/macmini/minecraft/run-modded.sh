#!/bin/bash
# NeoForge のサーバーを1本起動する。どのインスタンスかは環境変数で渡る(hosts/macmini.nix の
# minecraftServers を参照)。Paper 側 (run.sh) と分けてあるのは起動の形が違うため——本体の
# jar が無く、インストーラが展開した libraries を @引数ファイル経由で読ませる。
set -u

SERVER_DIR="${SERVER_DIR:?SERVER_DIR が未設定}"
JAVA="${JAVA_BIN:?JAVA_BIN が未設定}"
MEM="${SERVER_MEM:-3G}"
INSTALLER="${NEOFORGE_INSTALLER:?NEOFORGE_INSTALLER が未設定}"
VERSION="${NEOFORGE_VERSION:?NEOFORGE_VERSION が未設定}"

cd "$SERVER_DIR" || exit 1

ARGS="libraries/net/neoforged/neoforge/$VERSION/unix_args.txt"

# libraries だけは宣言できない。インストーラが Maven から集めてきて展開するもので、中身は
# 数百ファイルになる。その版がまだ展開されていなければ1回だけ走らせる(初回は数分かかる)。
# 版を上げると新しいパスになるので、ここが再び走って旧版は残る——戻したいときのために。
if [ ! -f "$ARGS" ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] NeoForge $VERSION を展開する (初回のみ)"
  "$JAVA" -jar "$INSTALLER" --installServer "$SERVER_DIR" || exit 1
fi

# 宣言された mod は store への symlink として置き直す。前回の分(= symlink)は毎回消すので、
# 宣言から外した mod は次の起動で居なくなる。手で入れた実体の jar には触らない。
mkdir -p mods
find mods -maxdepth 1 -type l -name '*.jar' -delete
for m in ${MODS:-}; do
  name=$(basename "$m")
  # store の名前は <hash>-<本来の名前>.jar。hash に - は入らないので先頭だけ落とせばいい。
  ln -sfn "$m" "mods/${name#*-}"
done

# Aikar's flags から AlwaysPreTouch を外し -Xms を小さくしてある。理由は run.sh と同じで、
# 無人時間が長く 24GB を AI スタックと分け合う機械だから。
exec "$JAVA" \
  -Xms512M "-Xmx$MEM" \
  -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 \
  -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC \
  -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M \
  -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 \
  -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 \
  -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 \
  -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1 \
  "@$ARGS" nogui
