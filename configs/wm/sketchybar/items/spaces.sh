#!/usr/bin/env bash
#
# ワークスペース表示 (omniwm) を、各ディスプレイ正しく振り分ける。
# WM への照会は helpers/wm.sh が稼働中のバックエンドに振り分ける。
#
# 仕組み:
#   sketchybar --reload 中の sketchybarrc 文脈からは `sketchybar --query` が
#   空を返す（自分自身が応答できない）ため、マッピングは外部の
#   ~/.config/sketchybar/helpers/display_watch.sh (launchd 常駐) が
#   事前計算して /tmp/sketchybar-omniwm-display.map に書き出している。
#   この spaces.sh はそのキャッシュを読むだけ。
#
#   キャッシュフォーマット (1行に "wm_monitor_id:sketchybar_display_index"):
#     1:2
#     2:1
#     3:3
#
# 依存:
#   - bash (連想配列)
#   - display_watch.sh が動いていること

sketchybar --add event omniwm_workspace_change

source "$CONFIG_DIR/helpers/wm.sh"

declare -A AERO_TO_SB
MAP_FILE=/tmp/sketchybar-omniwm-display.map

build_display_map() {
  if [ -r "$MAP_FILE" ]; then
    while IFS=':' read -r a s; do
      [ -n "$a" ] && [ -n "$s" ] && AERO_TO_SB[$a]="$s"
    done < "$MAP_FILE"
  fi
}

build_display_map

# 空のワークスペースを初期表示から隠すため、現在フォーカス中のワークスペースを控える
focused_ws=$(wm_focused_workspace)

for m in $(wm_list_monitors); do
  sb_display=${AERO_TO_SB[$m]:-$m}
  for i in $(wm_list_workspaces "$m" all); do
    sid=$i
    space=(
      space="$sid"
      icon="$sid"
      icon.highlight_color=$RED
      icon.padding_left=$(sc 6.68)
      icon.padding_right=$(sc 6.68)
      display=$sb_display
      padding_left=$(sc 1.34)
      padding_right=$(sc 1.34)
      label.padding_right=$(sc 13.37)
      label.color=$GREY
      label.highlight_color=$WHITE
      label.font="sketchybar-app-font:Regular:$(scf 14.0)"
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
                 --subscribe space.$sid mouse.clicked omniwm_workspace_change
    else
      sketchybar --add space space.$sid left \
                 --set space.$sid "${space[@]}" \
                 --subscribe space.$sid mouse.clicked omniwm_workspace_change
    fi

    apps=$(wm_workspace_apps "$sid")

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

    # 空 (アプリなし) かつ非フォーカスのワークスペースは非表示にする。
    # space_windows.sh がワークスペース切替時に drawing を再計算して戻す。
    if [ "$sid" != "0" ] && [ "${apps}" = "" ] && [ "$sid" != "$focused_ws" ]; then
      sketchybar --set space.$sid drawing=off
    fi
  done

done


space_creator=(
  drawing=off
  # drawing=off でも切替イベントで space_windows.sh を必ず走らせる。
  # (when_shown 既定のままだと非表示アイテムはイベントを受け取らず、
  #  空→フォーカス時に drawing を戻す再計算が動かない)
  updates=on
  icon=􀆊
  icon.font="$FONT:Heavy:$(scf 16.0)"
  padding_left=$(sc 6.68)
  padding_right=$(sc 5.35)
  label.drawing=off
  display=active
  #click_script='yabai -m space --create'
  script="$PLUGIN_DIR/space_windows.sh"
  icon.color=$WHITE
)

sketchybar --add item space_creator left               \
           --set space_creator "${space_creator[@]}"   \
           --subscribe space_creator omniwm_workspace_change
