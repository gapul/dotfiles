#!/bin/bash

source "$CONFIG_DIR/colors.sh"
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

ICON="􀇳"
ICON_COLOR_CURRENT="$ICON_COLOR"
LABEL_COLOR_CURRENT="$LABEL_COLOR"
if [[ "$BUNDLE" == net.mtgto.inputmethod.macSKK* ]]; then
  ICON="▽"
  case "$MODE" in
    *.ascii) LABEL="A" ;;
    *.hiragana) LABEL="あ" ;;
    *.katakana) LABEL="ア" ;;
    *.hankaku) LABEL="ｱ" ;;
    *.eisu) LABEL="Ａ" ;;
    *) LABEL="?" ;;
  esac

  if [ "$(defaults read net.mtgto.inputmethod.macSKK privateMode 2>/dev/null)" = "1" ]; then
    ICON="▽$LOCK"
    ICON_COLOR_CURRENT="$RED"
    LABEL_COLOR_CURRENT="$RED"
  fi
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

sketchybar --set "$NAME" icon="$ICON" icon.color="$ICON_COLOR_CURRENT" \
                             label="$LABEL" label.color="$LABEL_COLOR_CURRENT"
