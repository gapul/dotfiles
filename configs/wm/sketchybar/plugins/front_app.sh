#!/bin/bash

# Some events send additional information specific to the event in the $INFO
# variable. E.g. the front_app_switched event sends the name of the newly
# focused application in the $INFO variable:
# https://felixkratz.github.io/SketchyBar/config/events#events-and-scripting

source "$CONFIG_DIR/helpers/wm.sh"

OMNIWM_FOCUSED_MONITOR_NO=$(wm_focused_workspace)
OMNIWM_LIST_OF_WINDOWS_IN_FOCUSED_MONITOR=$(wm_workspace_apps "$OMNIWM_FOCUSED_MONITOR_NO")

if [ "$SENDER" = "front_app_switched" ]; then
  #echo name:$NAME INFO: $INFO SENDER: $SENDER, SID: $SID >> ~/aaaa
  sketchybar --set "$NAME" label="$INFO" icon.background.image="app.$INFO" icon.background.image.scale=0.8

  apps=$OMNIWM_LIST_OF_WINDOWS_IN_FOCUSED_MONITOR
  icon_strip=" "
  if [ "${apps}" != "" ]; then
    while read -r app
    do
      icon_strip+=" $($CONFIG_DIR/plugins/icon_map.sh "$app")"
    done <<< "${apps}"
  else
    icon_strip=" —"
  fi
  sketchybar --set space.$OMNIWM_FOCUSED_MONITOR_NO label="$icon_strip"
fi
