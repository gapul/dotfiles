#!/bin/bash

source "$HOME/.config/sketchybar-colors.sh"
source "$CONFIG_DIR/icons.sh"

SOURCES="$(defaults read com.apple.HIToolbox AppleSelectedInputSources 2>/dev/null)"
BUNDLE="$(printf '%s\n' "$SOURCES" | awk -F'= ' '
  /^[[:space:]]*"?Bundle ID"?[[:space:]]*=/ {
    value=$2
    gsub(/[;"]/,"",value)
    bundle=value
  }
  END { print bundle }
')"
MODE="$(printf '%s\n' "$SOURCES" | awk -F'= ' '
  /^[[:space:]]*"?Input Mode"?[[:space:]]*=/ {
    value=$2
    gsub(/[;"]/,"",value)
    mode=value
  }
  END { print mode }
')"
LAYOUT="$(printf '%s\n' "$SOURCES" | awk -F'= ' '
  /^[[:space:]]*"?KeyboardLayout Name"?[[:space:]]*=/ {
    value=$2
    gsub(/[;"]/,"",value)
    layout=value
  }
  END { print layout }
')"

# No icon: the ▽ SKK marker is carried in the label instead (see items/input_source.sh,
# which sets icon.drawing=off).
LABEL_COLOR_CURRENT="$LABEL_COLOR"
if [[ "$BUNDLE" == net.mtgto.inputmethod.macSKK* ]]; then
  case "$MODE" in
    *.ascii) MODE_LABEL="A" ;;
    *.hiragana) MODE_LABEL="あ" ;;
    *.katakana) MODE_LABEL="ア" ;;
    *.hankaku) MODE_LABEL="ｱ" ;;
    *.eisu) MODE_LABEL="Ａ" ;;
    *) MODE_LABEL="?" ;;
  esac

  # ▽ prefix (SKK marker) as part of the label. Private mode adds the lock and turns red.
  PREFIX="▽"
  if [ "$(defaults read net.mtgto.inputmethod.macSKK privateMode 2>/dev/null)" = "1" ]; then
    PREFIX="▽$LOCK"
    LABEL_COLOR_CURRENT="$RED"
  fi
  LABEL="$PREFIX$MODE_LABEL"
elif [ -n "$LAYOUT" ]; then
  LABEL="$LAYOUT"
else
  case "$MODE" in
    *halfwidth-katakana*) LABEL="ｱ" ;;
    *hiragana*|*.Japanese) LABEL="あ" ;;
    *katakana*|*.Katakana) LABEL="ア" ;;
    *direct*|*ascii*|*roman*|*.Roman) LABEL="A" ;;
    "") LABEL="?" ;;
    *) LABEL="${MODE##*.}" ;;
  esac
fi

sketchybar --set "$NAME" label="$LABEL" label.color="$LABEL_COLOR_CURRENT"
