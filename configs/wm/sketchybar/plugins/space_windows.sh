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

  # current workspace space border color
  sketchybar --set space.$AEROSPACE_FOCUSED_WORKSPACE icon.highlight=true \
                         label.highlight=true \
                         background.border_color=$GREY

  # prev workspace space border color
  sketchybar --set space.$AEROSPACE_PREV_WORKSPACE icon.highlight=false \
                         label.highlight=false \
                         background.border_color=$BACKGROUND_2

  # if [ "$AEROSPACE_FOCUSED_WORKSPACE" -gt 3 ]; then
  #   sketchybar --animate sin 10 --set space.$AEROSPACE_FOCUSED_WORKSPACE display=1
  # fi
  ## 全ワークスペースの "希望 display" を連想配列で組み立てる (後勝ち = focused 優先)
  declare -A want
  for m in $(aerospace list-monitors | awk '{print $1}'); do
    sb_d=$(aero_to_sb "$m")
    for i in $(aerospace list-workspaces --monitor $m --empty no); do
      want[$i]=$sb_d
    done
    for i in $(aerospace list-workspaces --monitor $m --empty); do
      want[$i]=0
    done
  done
  # focused workspace は空でも表示する (上書き)
  want[$AEROSPACE_FOCUSED_WORKSPACE]=$SB_FOCUSED_DISPLAY

  # workspace 昇順に展開
  desired=$(for k in "${!want[@]}"; do echo "$k=${want[$k]}"; done | sort)

  # 前回と同じなら何もしない (WindowServer 負荷削減)
  STATE_FILE=/tmp/sketchybar-space-display.state
  prev=$(cat "$STATE_FILE" 2>/dev/null)
  if [ "$desired" != "$prev" ]; then
    args=()
    while IFS='=' read -r ws disp; do
      [ -z "$ws" ] && continue
      args+=(--set space.$ws display=$disp)
    done <<< "$desired"
    if [ ${#args[@]} -gt 0 ]; then
      sketchybar "${args[@]}"
    fi
    printf '%s\n' "$desired" > "$STATE_FILE"
  fi

fi
