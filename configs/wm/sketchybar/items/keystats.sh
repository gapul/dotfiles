#!/bin/bash

keystats=(
  icon=􀇳
  icon.font="$FONT:Bold:$(scf 13.0)"
  icon.padding_right=2
  label.font="$FONT:Semibold:$(scf 13.0)"
  label.color=$LABEL_COLOR
  script="$PLUGIN_DIR/keystats.sh"
  update_freq=30
  click_script="$PLUGIN_DIR/keystats.sh click"
)

sketchybar --add item keystats right \
           --set keystats "${keystats[@]}" \
           --subscribe keystats system_woke
