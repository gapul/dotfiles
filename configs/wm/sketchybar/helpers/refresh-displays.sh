#!/bin/bash
#
# sketchybar のディスプレイ→ワークスペース対応を再構築する手動コマンド。
#
# 用途:
#   ディスプレイを抜き差し / 配置変更 / メイン切替 した後に1回叩く。
#   各 WM モニターのワークスペースが、対応する物理ディスプレイの
#   sketchybar に正しく振り分けられた状態に再構成する。
#
# 仕組み:
#   1. sketchybar --query displays から arrangement-id と frame.x を取得
#   2. frame.x 昇順にソート (= WM の左→右順と一致)
#   3. /tmp/sketchybar-omniwm-display.map に "wmMonitorID:sbDisplay" で書き出し
#   4. sketchybar --reload で spaces.sh を再実行
#      (spaces.sh は上記マップを読んで display= を設定)

set -e

MAP_FILE=/tmp/sketchybar-omniwm-display.map
SB=/opt/homebrew/bin/sketchybar
JQ="$HOME/.nix-profile/bin/jq" # jq は nix 管理 (homebrew には無い)
# shellcheck source=/dev/null
. "${BASH_SOURCE%/*}/wm.sh"

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

wm_ids=$(wm_list_monitors_by_x)

n_sorted=$(echo "$sorted" | wc -l | tr -d ' ')
n_wm=$(echo "$wm_ids" | wc -l | tr -d ' ')
if [ "$n_sorted" != "$n_wm" ]; then
  echo "sketchybar-refresh: ディスプレイ数の不一致 (sketchybar=$n_sorted WM=$n_wm)" >&2
  echo "  sketchybar や OmniWM を再起動してから再試行してください。" >&2
  exit 1
fi

paste -d':' <(echo "$wm_ids") <(echo "$sorted") > "$MAP_FILE.tmp"
mv "$MAP_FILE.tmp" "$MAP_FILE"

echo "sketchybar-refresh: マップを更新しました ($MAP_FILE)"
awk -F':' '{ printf "  WM monitor #%s -> sketchybar display %s\n", $1, $2 }' "$MAP_FILE"

# sketchybar --reload は items を再ソースしない (既存 space アイテムの display 設定を上書きしない)
# プロセスごと再起動して spaces.sh を完全に再実行させる必要がある
launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.sketchybar" >/dev/null 2>&1
echo "sketchybar-refresh: sketchybar を再起動しました"
