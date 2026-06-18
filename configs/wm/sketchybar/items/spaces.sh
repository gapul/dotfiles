#!/bin/bash
#
# AeroSpace ワークスペース表示を、各ディスプレイ正しく振り分ける。
#
# 仕組み:
#   sketchybar --reload 中の sketchybarrc 文脈からは `sketchybar --query` が
#   空を返す（自分自身が応答できない）ため、マッピングは外部の
#   ~/.config/sketchybar/helpers/display_watch.sh (launchd 常駐) が
#   事前計算して /tmp/sketchybar-aero-display.map に書き出している。
#   この spaces.sh はそのキャッシュを読むだけ。
#
#   キャッシュフォーマット (1行に "aerospace_id:sketchybar_display_index"):
#     1:2
#     2:1
#     3:3
#
# 依存:
#   - bash (連想配列)
#   - display_watch.sh が動いていること

sketchybar --add event aerospace_workspace_change

declare -A AERO_TO_SB
MAP_FILE=/tmp/sketchybar-aero-display.map

build_display_map() {
  if [ -r "$MAP_FILE" ]; then
    while IFS=':' read -r a s; do
      [ -n "$a" ] && [ -n "$s" ] && AERO_TO_SB[$a]="$s"
    done < "$MAP_FILE"
  fi
}

build_display_map

for m in $(aerospace list-monitors | awk '{print $1}'); do
  sb_display=${AERO_TO_SB[$m]:-$m}
  for i in $(aerospace list-workspaces --monitor $m); do
    sid=$i
    space=(
      space="$sid"
      icon="$sid"
      icon.highlight_color=$RED
      icon.padding_left=10
      icon.padding_right=10
      display=$sb_display
      padding_left=2
      padding_right=2
      label.padding_right=20
      label.color=$GREY
      label.highlight_color=$WHITE
      label.font="sketchybar-app-font:Regular:16.0"
      label.y_offset=-1
      background.color=$BACKGROUND_1
      background.border_color=$BACKGROUND_2
      script="$PLUGIN_DIR/space.sh"
    )

    if [ "$sid" = "0" ]; then
      # `item` には `space=` プロパティが無いので除外する
      space_item=("${space[@]:1}")
      sketchybar --add item space.$sid left \
                 --set space.$sid "${space_item[@]}" \
                 --subscribe space.$sid mouse.clicked aerospace_workspace_change
    else
      sketchybar --add space space.$sid left \
                 --set space.$sid "${space[@]}" \
                 --subscribe space.$sid mouse.clicked aerospace_workspace_change
    fi

    apps=$(aerospace list-windows --workspace $sid | awk -F'|' '{gsub(/^ *| *$/, "", $2); print $2}')

    icon_strip=" "
    if [ "${apps}" != "" ]; then
      while read -r app
      do
        icon_strip+=" $($CONFIG_DIR/plugins/icon_map.sh "$app")"
      done <<< "${apps}"
    else
      icon_strip=" —"
    fi

    sketchybar --set space.$sid label="$icon_strip"
  done

done


space_creator=(
  icon=􀆊
  icon.font="$FONT:Heavy:16.0"
  padding_left=10
  padding_right=8
  label.drawing=off
  display=active
  #click_script='yabai -m space --create'
  script="$PLUGIN_DIR/space_windows.sh"
  #script="$PLUGIN_DIR/aerospace.sh"
  icon.color=$WHITE
)

sketchybar --add item space_creator left               \
           --set space_creator "${space_creator[@]}"   \
           --subscribe space_creator aerospace_workspace_change
