#!/bin/bash

input_source=(
  icon.drawing=off
  label.font="$FONT:Semibold:$(scf 13.0)"
  label.align=center
  script="$PLUGIN_DIR/input_source.sh"
  update_freq=1
  click_script="$PLUGIN_DIR/input_source_click.sh"
)

sketchybar --add item input_source right \
           --set input_source "${input_source[@]}" \
           --subscribe input_source system_woke
