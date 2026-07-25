#!/bin/bash

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

sketchybar --set "$NAME" icon="$ICON" label="$LABEL"
