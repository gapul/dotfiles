#!/bin/bash

memory=(
  icon=$MEM_ICON
  icon.color=$GREEN
  icon.font="$FONT:Bold:$(scf 14.0)"
  label.drawing=off
  update_freq=4
  script="$PLUGIN_DIR/memory.sh"
  click_script="$PLUGIN_DIR/open_tui.sh system"
)

sketchybar --add item memory right \
           --set memory "${memory[@]}"
