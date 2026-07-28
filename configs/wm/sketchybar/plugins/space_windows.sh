#!/usr/bin/env bash

source "$CONFIG_DIR/colors.sh"

AEROSPACE_FOCUSED_MONITOR=$(aerospace list-monitors --focused | awk '{print $1}')
AEROSAPCE_WORKSPACE_FOCUSED_MONITOR=$(aerospace list-workspaces --monitor focused --empty no)
AEROSPACE_EMPTY_WORKESPACE=$(aerospace list-workspaces --monitor focused --empty)

# aerospace monitor id -> sketchybar display index
# (sketchybar-refresh が /tmp/sketchybar-aero-display.map に書き出しているマップ)
MAP_FILE=/tmp/sketchybar-aero-display.map
aero_to_sb() {
  local aero_id="$1"
  if [ -r "$MAP_FILE" ]; then
    local mapped
    mapped=$(awk -F':' -v id="$aero_id" '$1==id{print $2; exit}' "$MAP_FILE")
    if [ -n "$mapped" ]; then
      echo "$mapped"
      return
    fi
  fi
  # フォールバック: そのまま返す (1画面のときなど)
  echo "$aero_id"
}
SB_FOCUSED_DISPLAY=$(aero_to_sb "$AEROSPACE_FOCUSED_MONITOR")

reload_workspace_icon() {
  # echo reload_workspace_icon "$@" >> ~/aaaa
  apps=$(aerospace list-windows --workspace "$@" | awk -F'|' '{gsub(/^ *| *$/, "", $2); print $2}')

  icon_strip=" "
  if [ "${apps}" != "" ]; then
    while read -r app
    do
      icon_strip+=" $($CONFIG_DIR/plugins/icon_map.sh "$app")"
    done <<< "${apps}"
  else
    icon_strip=" —"
  fi

  # shellcheck disable=SC2068,SC2145  # space.$@ は単一 workspace 名の展開で意図通り (動作実績あり)
  sketchybar --set space.$@ label="$icon_strip"
}

if [ "$SENDER" = "aerospace_workspace_change" ]; then

  # if [ $i = "$FOCUSED_WORKSPACE" ]; then
  #   sketchybar --set space.$FOCUSED_WORKSPACE background.drawing=on
  # else
  #   sketchybar --set space.$FOCUSED_WORKSPACE background.drawing=off
  # fi
  #echo 'space_windows_change: '$AEROSPACE_FOCUSED_WORKSPACE >> ~/aaaa
  #echo space: $space >> ~/aaaa
  #space="$(echo "$INFO" | jq -r '.space')"
  #apps="$(echo "$INFO" | jq -r '.apps | keys[]')"
  # apps=$(aerospace list-windows --workspace $AEROSPACE_FOCUSED_WORKSPACE | awk -F'|' '{gsub(/^ *| *$/, "", $2); print $2}')
  #
  # icon_strip=" "
  # if [ "${apps}" != "" ]; then
  #   while read -r app
  #   do
  #     icon_strip+=" $($CONFIG_DIR/plugins/icon_map.sh "$app")"
  #   done <<< "${apps}"
  # else
  #   icon_strip=" —"
  # fi

  if [ -n "$AEROSPACE_PREV_WORKSPACE" ]; then
    reload_workspace_icon "$AEROSPACE_PREV_WORKSPACE"
    reload_workspace_icon "$AEROSPACE_FOCUSED_WORKSPACE"
  else
    for ws in $(aerospace list-workspaces --all); do
      reload_workspace_icon "$ws"
    done
  fi

  #sketchybar --animate sin 10 --set space.$space label="$icon_strip"

  # ハイライトは focused だけ ON、それ以外は全て OFF に確定させる。
  #   個別 space.sh も同じ結論を出すので、実行順に関係なく最終状態が一致する
  #   (focused/prev だけ触っていた旧実装は取り残しが出てレースになっていた)。
  hl_args=()
  for ws in $(aerospace list-workspaces --all); do
    if [ "$ws" = "$AEROSPACE_FOCUSED_WORKSPACE" ]; then
      hl_args+=(--set space.$ws icon.highlight=true label.highlight=true background.border_color=$GREY)
    else
      hl_args+=(--set space.$ws icon.highlight=false label.highlight=false background.border_color=$BACKGROUND_2)
    fi
  done
  [ ${#hl_args[@]} -gt 0 ] && sketchybar "${hl_args[@]}"

  # if [ "$AEROSPACE_FOCUSED_WORKSPACE" -gt 3 ]; then
  #   sketchybar --animate sin 10 --set space.$AEROSPACE_FOCUSED_WORKSPACE display=1
  # fi
  ## 全ワークスペースの "希望 display / drawing" を連想配列で組み立てる (後勝ち = focused 優先)
  #   空のワークスペースは drawing=off で非表示にする (display=0 では消えない)。
  declare -A want_disp
  declare -A want_draw
  for m in $(aerospace list-monitors | awk '{print $1}'); do
    sb_d=$(aero_to_sb "$m")
    for i in $(aerospace list-workspaces --monitor $m --empty no); do
      want_disp[$i]=$sb_d
      want_draw[$i]=on
    done
    for i in $(aerospace list-workspaces --monitor $m --empty); do
      want_disp[$i]=$sb_d
      want_draw[$i]=off
    done
  done
  # focused workspace は空でも表示する (上書き)
  want_disp[$AEROSPACE_FOCUSED_WORKSPACE]=$SB_FOCUSED_DISPLAY
  want_draw[$AEROSPACE_FOCUSED_WORKSPACE]=on

  # workspace 昇順に展開 ("ws=display:drawing")
  desired=$(for k in "${!want_disp[@]}"; do echo "$k=${want_disp[$k]}:${want_draw[$k]}"; done | sort)

  # 前回と同じなら何もしない (WindowServer 負荷削減)
  STATE_FILE=/tmp/sketchybar-space-display.state
  prev=$(cat "$STATE_FILE" 2>/dev/null)
  if [ "$desired" != "$prev" ]; then
    args=()
    while IFS='=' read -r ws val; do
      [ -z "$ws" ] && continue
      disp=${val%%:*}
      draw=${val##*:}
      args+=(--set space.$ws display=$disp drawing=$draw)
    done <<< "$desired"
    if [ ${#args[@]} -gt 0 ]; then
      sketchybar "${args[@]}"
    fi
    printf '%s\n' "$desired" > "$STATE_FILE"
  fi

fi
