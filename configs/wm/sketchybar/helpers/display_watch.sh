#!/bin/bash
#
# ディスプレイ構成の変化を監視し、
#   1) aerospace monitor id -> sketchybar display index のマッピングを再計算
#      → /tmp/sketchybar-aero-display.map に保存
#   2) sketchybar --reload を発火
#
# sketchybar --reload 中の sketchybarrc 文脈からは sketchybar --query が
# 空を返すため、マッピングは "reload 前" にここで計算してキャッシュする。

MAP_FILE=/tmp/sketchybar-aero-display.map
DP=/opt/homebrew/bin/displayplacer
SB=/opt/homebrew/bin/sketchybar
JQ="$HOME/.nix-profile/bin/jq" # jq は nix 管理 (homebrew には無い)
AS=/opt/homebrew/bin/aerospace

write_map() {
  # sketchybar が認識している全ディスプレイを frame.x 昇順ソートし
  # arrangement-id の列を作る (= aerospace の monitor 順と対応する想定)
  # reload直後など query が一時的に空を返すことがあるのでリトライする
  local sorted=""
  local i
  for i in 1 2 3 4 5 6; do
    sorted=$("$SB" --query displays 2>/dev/null | "$JQ" -r 'sort_by(.frame.x) | .[]."arrangement-id"')
    [ -n "$sorted" ] && break
    sleep 1
  done
  [ -z "$sorted" ] && return 1

  # WM のモニター ID 列 (左→右順)。omniwm 稼働中は omniwmctl から取る
  # ("display:N" → N)。frame.x 昇順で sketchybar 側と同じ並び順にする。
  local aero_ids
  if pgrep -xq OmniWM; then
    aero_ids=$(/opt/homebrew/bin/omniwmctl query displays --fields id,frame --format json 2>/dev/null |
      "$JQ" -r '.result.payload.displays | sort_by(.frame.x) | .[].id | sub("^display:"; "")')
  else
    aero_ids=$("$AS" list-monitors | awk '{print $1}')
  fi

  # 個数が一致しないなら書き換えない（一時的な不整合の可能性）
  local n_sorted n_aero
  n_sorted=$(echo "$sorted" | wc -l | tr -d ' ')
  n_aero=$(echo "$aero_ids" | wc -l | tr -d ' ')
  if [ "$n_sorted" != "$n_aero" ]; then
    return 1
  fi

  # ペアにして map を書き出す
  paste -d':' <(echo "$aero_ids") <(echo "$sorted") > "$MAP_FILE.tmp"
  mv "$MAP_FILE.tmp" "$MAP_FILE"
}

# 初回は必ず書き出す
write_map
"$SB" --reload >/dev/null 2>&1

prev=""
while :; do
  if [ -x "$DP" ]; then
    cur=$("$DP" list 2>/dev/null | grep -E "^(Persistent screen id|Origin|Resolution|Enabled):" | shasum | cut -d' ' -f1)
  else
    cur=""
  fi
  if [ -n "$prev" ] && [ "$cur" != "$prev" ]; then
    # 構成変化: マッピングを更新してから reload
    write_map
    "$SB" --reload >/dev/null 2>&1
  fi
  prev="$cur"
  sleep 3
done
