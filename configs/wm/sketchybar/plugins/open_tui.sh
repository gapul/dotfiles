#!/bin/bash

NIX_BIN="$HOME/.local/state/nix/profile/bin"

case "$1" in
  calendar)
    TITLE="Calendar"
    COMMAND="$NIX_BIN/calcurse"
    ;;
  music)
    TITLE="Music"
    COMMAND="$NIX_BIN/rmpc"
    ;;
  system)
    TITLE="System Monitor"
    COMMAND="$NIX_BIN/btm"
    ;;
  *)
    exit 1
    ;;
esac

[ -x "$COMMAND" ] || exit 1

open -na Ghostty.app --args --title="$TITLE" -e "$COMMAND"
