#!/bin/bash

source "$CONFIG_DIR/icons.sh"

if [ -n "$INFO" ]; then
  VOL="$INFO"
else
  VOL="$(osascript -e 'output volume of (get volume settings)' 2>/dev/null)"
fi
[ -z "$VOL" ] && VOL=0

TRANSPORT="$(/usr/sbin/system_profiler SPAudioDataType 2>/dev/null \
  | awk '/Default Output Device: Yes/{flag=1} flag && /Transport:/{print $2; exit}')"

if [ "$TRANSPORT" = "Bluetooth" ]; then
  ICON="$HEADPHONES"
else
  case "$VOL" in
    [6-9][0-9]|100) ICON="$VOLUME_100" ;;
    [3-5][0-9])     ICON="$VOLUME_66"  ;;
    [1-2][0-9])     ICON="$VOLUME_33"  ;;
    [1-9])          ICON="$VOLUME_10"  ;;
    0)              ICON="$VOLUME_0"   ;;
    *)              ICON="$VOLUME_100" ;;
  esac
fi

sketchybar --set volume_icon icon="$ICON"
