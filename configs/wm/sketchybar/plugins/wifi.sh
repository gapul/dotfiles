#!/bin/bash

source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

DEVICE="en0"

POWER="$(/usr/sbin/networksetup -getairportpower "$DEVICE" 2>/dev/null | awk '{print $NF}')"
ASSOCIATED="$(/sbin/ifconfig "$DEVICE" 2>/dev/null | grep -c 'status: active')"

if [ "$POWER" != "On" ] || [ "$ASSOCIATED" -eq 0 ]; then
  sketchybar --set "$NAME" icon="$WIFI_DISCONNECTED" icon.color="$GREY" label.drawing=off
  exit 0
fi

INFO="$(/usr/sbin/system_profiler SPAirPortDataType 2>/dev/null \
  | sed -n '/Current Network Information/,/Other Local Wi-Fi Networks/p')"

RSSI="$(printf '%s\n' "$INFO" | awk '/Signal \/ Noise/ {print $4; exit}')"

ICON="$WIFI_CONNECTED"
if [ -n "$RSSI" ] && [ "$RSSI" -lt 0 ] 2>/dev/null; then
  if [ "$RSSI" -ge -50 ]; then
    COLOR="$BLUE"
  elif [ "$RSSI" -ge -60 ]; then
    COLOR="$GREEN"
  elif [ "$RSSI" -ge -70 ]; then
    COLOR="$YELLOW"
  elif [ "$RSSI" -ge -80 ]; then
    COLOR="$ORANGE"
  else
    COLOR="$RED"
    ICON="$WIFI_WARNING"
  fi
else
  COLOR="$GREEN"
fi

sketchybar --set "$NAME" icon="$ICON" icon.color="$COLOR" label.drawing=off
