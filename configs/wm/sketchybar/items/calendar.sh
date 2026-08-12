#!/bin/bash

calendar=(
  icon=􀐫
  icon.font="$FONT:Black:$(scf 12.0)"
  icon.padding_right=0
  label.align=right
  padding_left=$(sc 10.02)
  update_freq=30
  script="$PLUGIN_DIR/calendar.sh"
  click_script="$PLUGIN_DIR/open_tui.sh calendar"
)

sketchybar --add item calendar right       \
           --set calendar "${calendar[@]}" \
           --subscribe calendar system_woke
