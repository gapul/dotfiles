#!/bin/sh

wifi=(
  icon=$WIFI_DISCONNECTED
  icon.color=$GREY
  icon.font="$FONT:Bold:14.0"
  label.font="$FONT:Semibold:13.0"
  label.color=$LABEL_COLOR
  label.max_chars=20
  script="$PLUGIN_DIR/wifi.sh"
  update_freq=120
  click_script="open /System/Library/PreferencePanes/Network.prefPane"
)

sketchybar --add item wifi right \
           --set wifi "${wifi[@]}" \
           --subscribe wifi wifi_change system_woke
