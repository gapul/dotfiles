#!/bin/bash

KEYSTATS_BIN="$HOME/.local/bin/keystats"

if [ "$1" = "click" ]; then
  open -a Keystats
  exit 0
fi

if [ ! -x "$KEYSTATS_BIN" ]; then
  sketchybar --set "$NAME" drawing=off
  exit 0
fi

TODAY="$("$KEYSTATS_BIN" today 2>/dev/null)"

if [[ "$TODAY" =~ ^[0-9]+$ ]]; then
  sketchybar --set "$NAME" drawing=on label="$TODAY"
else
  sketchybar --set "$NAME" drawing=on label="—"
fi
