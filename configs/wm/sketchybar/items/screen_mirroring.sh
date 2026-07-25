#!/bin/bash

screen_mirroring=(
  icon=􀑡
  icon.font="$FONT:Bold:$(scf 15.0)"
  icon.color=$GREY
  label.drawing=off
  script="$PLUGIN_DIR/screen_mirroring.sh"
  update_freq=30
  click_script="$PLUGIN_DIR/screen_mirroring.sh click"
)

sketchybar --add item screen_mirroring right \
           --set screen_mirroring "${screen_mirroring[@]}" \
           --subscribe screen_mirroring display_change system_woke
