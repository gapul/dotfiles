#!/bin/bash

cpu_percent=(
  icon=$CPU_ICON
  icon.color=$GREEN
  icon.font="$FONT:Bold:14.0"
  label.drawing=off
  update_freq=4
  script="$PLUGIN_DIR/cpu.sh"
)

sketchybar --add item cpu.percent right \
           --set cpu.percent "${cpu_percent[@]}"
