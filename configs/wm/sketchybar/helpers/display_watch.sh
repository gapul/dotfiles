#!/bin/bash
#
# ディスプレイ構成の変化を監視し、
#   1) omniwm monitor id -> sketchybar display index のマッピングを再計算
#      → /tmp/sketchybar-omniwm-display.map に保存
#   2) 外部モニタ (メインディスプレイ以外) の display index 一覧を再計算
#      → /tmp/sketchybar-ext-displays に保存 (ext インスタンスの描画先)
#   3) sketchybar --reload を発火 (両インスタンス)
#
# sketchybar --reload 中の sketchybarrc 文脈からは sketchybar --query が
# 空を返すため、マッピングは "reload 前" にここで計算してキャッシュする。

MAP_FILE=/tmp/sketchybar-omniwm-display.map
EXT_FILE=/tmp/sketchybar-ext-displays
DP=/opt/homebrew/bin/displayplacer
SB=/opt/homebrew/bin/sketchybar
SB_ALL="${BASH_SOURCE%/*}/sb-all.sh"
JQ="$HOME/.nix-profile/bin/jq" # jq は nix 管理 (homebrew には無い)
# WM 照会は helpers/wm.sh に集約
# shellcheck source=/dev/null
. "${BASH_SOURCE%/*}/wm.sh"

write_map() {
  # sketchybar が認識している全ディスプレイを frame.x 昇順ソートし
  # arrangement-id の列を作る (= omniwm の monitor 順と対応する想定)
  # reload直後など query が一時的に空を返すことがあるのでリトライする
  local sorted=""
  local i
  for i in 1 2 3 4 5 6; do
    sorted=$("$SB" --query displays 2>/dev/null | "$JQ" -r 'sort_by(.frame.x) | .[]."arrangement-id"')
    [ -n "$sorted" ] && break
    sleep 1
  done
  [ -z "$sorted" ] && return 1

  # WM のモニター ID 列 (左→右順)。frame.x 昇順で sketchybar 側と同じ並び順にする。
  local wm_ids
  wm_ids=$(wm_list_monitors_by_x)

  # 個数が一致しないなら書き換えない（一時的な不整合の可能性）
  local n_sorted n_wm
  n_sorted=$(echo "$sorted" | wc -l | tr -d ' ')
  n_wm=$(echo "$wm_ids" | wc -l | tr -d ' ')
  if [ "$n_sorted" != "$n_wm" ]; then
    return 1
  fi

  # ペアにして map を書き出す
  paste -d':' <(echo "$wm_ids") <(echo "$sorted") > "$MAP_FILE.tmp"
  mv "$MAP_FILE.tmp" "$MAP_FILE"
}

write_ext_displays() {
  # 外部モニタ用インスタンス (sketchybar-ext) が描くディスプレイ番号。
  # CG 座標ではメインディスプレイの原点が必ず (0,0) なので、それ以外を外部とみなす。
  # 「メイン = メニューバーを持つ画面」なので、内蔵を主にしている限り内蔵が外れる。
  # (外部をメインにしている場合は大小が逆になる。そのときは System Settings 側の
  #  主ディスプレイを戻すか、内蔵/外部の寸法定義を入れ替えること)
  local json ext
  json=$("$SB" --query displays 2>/dev/null)
  # ディスプレイスリープ中などは空配列が返る。前回値を残したいので触らない。
  [ -z "$json" ] && return 1
  [ "$(echo "$json" | tr -d '[:space:]')" = "[]" ] && return 1

  ext=$(echo "$json" | "$JQ" -r '[.[] | select(.frame.x != 0 or .frame.y != 0) | ."arrangement-id"] | join(",")')
  printf '%s' "$ext" > "$EXT_FILE.tmp"
  mv "$EXT_FILE.tmp" "$EXT_FILE"
}

# 初回は必ず書き出す
write_map
write_ext_displays
"$SB_ALL" --reload

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
    write_ext_displays
    "$SB_ALL" --reload
  fi
  prev="$cur"
  sleep 3
done
