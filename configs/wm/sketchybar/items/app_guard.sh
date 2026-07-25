#!/bin/bash

# 常時起動していてほしいアプリが落ちていたら警告を出す item。
# 監視対象は expected_apps.conf。全て起動中なら自動で非表示になる。

app_guard=(
  icon=􀁢
  icon.font="$FONT:Bold:$(scf 14.0)"
  icon.color=$GREEN
  label.font="$FONT:Semibold:$(scf 12.0)"
  label.color=$RED
  label.padding_left=2
  label.drawing=off
  script="$PLUGIN_DIR/app_guard.sh"
  update_freq=15
  click_script="$PLUGIN_DIR/app_guard.sh click"
)

sketchybar --add item app_guard right \
           --set app_guard "${app_guard[@]}" \
           --subscribe app_guard system_woke front_app_switched
