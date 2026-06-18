#!/bin/bash

source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

DATA="$(/usr/sbin/system_profiler SPBluetoothDataType 2>/dev/null)"
STATE="$(echo "$DATA" | awk '/^[[:space:]]+State:/ {print $2; exit}')"

if [ "$STATE" != "On" ]; then
  sketchybar --set "$NAME" icon="$BLUETOOTH_OFF" icon.color="$GREY" label.drawing=off
  exit 0
fi

# Count connected devices: items under "Connected:" section, before "Not Connected:"
CONNECTED_COUNT="$(echo "$DATA" | awk '
  /^[[:space:]]+Connected:[[:space:]]*$/  { in_conn=1; next }
  /^[[:space:]]+Not Connected:[[:space:]]*$/ { in_conn=0 }
  in_conn && /^[[:space:]]{10}[^[:space:]]/ { c++ }
  END { print c+0 }
')"

if [ "$CONNECTED_COUNT" -gt 0 ]; then
  sketchybar --set "$NAME" \
    icon="$BLUETOOTH_CONNECTED" icon.color="$BLUE" \
    label="$CONNECTED_COUNT" label.drawing=on
else
  sketchybar --set "$NAME" \
    icon="$BLUETOOTH_ON" icon.color="$WHITE" \
    label.drawing=off
fi
