#!/bin/bash

KEYSTATS_BIN="$(command -v keystats 2>/dev/null)"
# /run/current-system/sw/bin: keystats は cask をやめて nix パッケージになったので、CLI は
# systemPackages の出力先にいる。PATH 頼みだけだと launchd 起動のバーからは見えない。
for c in /run/current-system/sw/bin/keystats /opt/homebrew/bin/keystats "$HOME/.local/bin/keystats"; do
  [ -x "$KEYSTATS_BIN" ] && break
  KEYSTATS_BIN="$c"
done

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
