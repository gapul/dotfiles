#!/bin/bash

# スリープ無効中 (nosleep on) だけ出るコーヒーアイコン。クリックで解除。
nosleep=(
  icon=􀸙
  icon.font="$FONT:Bold:$(scf 14.0)"
  icon.color=$YELLOW
  label.drawing=off
  drawing=off
  updates=on # drawing=off の間も状態を見に行くので既定の when_shown は使えない (点いたまま気付けなくなる)
  update_freq=30
  script="$PLUGIN_DIR/nosleep.sh"
  click_script="$PLUGIN_DIR/nosleep.sh off"
)

sketchybar --add item nosleep right \
  --set nosleep "${nosleep[@]}" \
  --subscribe nosleep system_woke power_source_change
