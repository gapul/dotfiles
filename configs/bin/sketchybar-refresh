#!/bin/bash
#
# sketchybar のディスプレイ→ワークスペース対応を再構築する手動コマンド。
#
# 用途:
#   ディスプレイを抜き差し / 配置変更 / メイン切替 した後に1回叩く。
#   各 aerospace モニターのワークスペースが、対応する物理ディスプレイの
#   sketchybar に正しく振り分けられた状態に再構成する。
#
# 仕組み:
#   1. sketchybar --query displays から arrangement-id と frame.x を取得
#   2. frame.x 昇順にソート (= aerospace の左→右順と一致)
#   3. /tmp/sketchybar-aero-display.map に "aerospaceID:sbDisplay" で書き出し
#   4. sketchybar --reload で spaces.sh を再実行
#      (spaces.sh は上記マップを読んで display= を設定)

set -e

MAP_FILE=/tmp/sketchybar-aero-display.map
SB=/opt/homebrew/bin/sketchybar
JQ=/opt/homebrew/bin/jq
AS=/opt/homebrew/bin/aerospace

# reload直後の query は空を返すことがあるのでリトライ
sorted=""
for _ in 1 2 3 4 5 6 7 8; do
  sorted=$("$SB" --query displays 2>/dev/null | "$JQ" -r 'sort_by(.frame.x) | .[]."arrangement-id"')
  [ -n "$sorted" ] && break
  sleep 0.5
done

if [ -z "$sorted" ]; then
  echo "sketchybar-refresh: sketchybar --query displays が空を返しました。sketchybar が起動しているか確認してください。" >&2
  exit 1
fi

aero_ids=$("$AS" list-monitors | awk '{print $1}')

n_sorted=$(echo "$sorted" | wc -l | tr -d ' ')
n_aero=$(echo "$aero_ids" | wc -l | tr -d ' ')
if [ "$n_sorted" != "$n_aero" ]; then
  echo "sketchybar-refresh: ディスプレイ数の不一致 (sketchybar=$n_sorted aerospace=$n_aero)" >&2
  echo "  sketchybar や aerospace を再起動してから再試行してください。" >&2
  exit 1
fi

paste -d':' <(echo "$aero_ids") <(echo "$sorted") > "$MAP_FILE.tmp"
mv "$MAP_FILE.tmp" "$MAP_FILE"

echo "sketchybar-refresh: マップを更新しました ($MAP_FILE)"
awk -F':' '{
  cmd = "/opt/homebrew/bin/aerospace list-monitors | awk -F\"|\" -v id=" $1 " \"\\$1+0==id{sub(/^ /,\\\"\\\",\\$2);print \\$2}\""
  cmd | getline name; close(cmd)
  printf "  aerospace #%s (%s) -> sketchybar display %s\n", $1, name, $2
}' "$MAP_FILE"

# sketchybar --reload は items を再ソースしない (既存 space アイテムの display 設定を上書きしない)
# プロセスごと再起動して spaces.sh を完全に再実行させる必要がある
/opt/homebrew/bin/brew services restart sketchybar >/dev/null 2>&1
echo "sketchybar-refresh: sketchybar を再起動しました"
