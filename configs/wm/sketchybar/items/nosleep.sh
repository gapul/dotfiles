#!/bin/bash

# スリープ無効 (nosleep) の状態表示とトグル。黄 = 無効中 (蓋を閉じても寝ない) / 灰 = 通常。
nosleep=(
  icon=􀸙
  icon.font="$FONT:Bold:$(scf 14.0)"
  icon.color=$GREY
  label.drawing=off
  update_freq=30
  script="$PLUGIN_DIR/nosleep.sh"
  click_script="$PLUGIN_DIR/nosleep.sh toggle"
)

sketchybar --add item nosleep right \
  --set nosleep "${nosleep[@]}" \
  --subscribe nosleep system_woke power_source_change
