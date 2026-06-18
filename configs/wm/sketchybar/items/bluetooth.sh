#!/bin/sh

bluetooth=(
  icon=$BLUETOOTH_OFF
  icon.color=$GREY
  icon.font="JetBrainsMono Nerd Font:Bold:16.0"
  label.font="$FONT:Semibold:13.0"
  label.color=$LABEL_COLOR
  script="$PLUGIN_DIR/bluetooth.sh"
  update_freq=60
  click_script="open /System/Library/PreferencePanes/Bluetooth.prefPane"
)

sketchybar --add item bluetooth right \
           --set bluetooth "${bluetooth[@]}" \
           --subscribe bluetooth system_woke
