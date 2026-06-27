#!/bin/bash
#
# media-control の出力は artworkData (巨大な base64) を含むので、
# python3 にパイプすると毎回 MB 単位のデータを処理することになる。
# jq で必要なフィールドだけ抜き出して軽量化。

source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

# 必要なフィールドだけ抽出 (artworkData は無視)
RESULT=$(/opt/homebrew/bin/media-control get 2>/dev/null \
  | "$HOME/.nix-profile/bin/jq" -r '
      if . == null or (. | type) != "object" then
        "none\t\t"
      else
        ((.playing // (.playbackRate // 0) > 0) | if . then "playing" else "paused" end)
        + "\t" + ((.title // "") | gsub("\t"; " "))
        + "\t" + ((.artist // "") | gsub("\t"; " "))
      end
    ' 2>/dev/null)

if [ -z "$RESULT" ]; then
  sketchybar --set "$NAME" drawing=off
  exit 0
fi

IFS=$'\t' read -r STATUS TITLE ARTIST <<< "$RESULT"

if [ "$STATUS" != "playing" ]; then
  sketchybar --set "$NAME" drawing=off
  exit 0
fi

if [ -n "$TITLE" ] && [ -n "$ARTIST" ]; then
  LABEL="$TITLE — $ARTIST"
elif [ -n "$TITLE" ]; then
  LABEL="$TITLE"
else
  LABEL="$ARTIST"
fi

sketchybar --set "$NAME" icon="$MUSIC_PLAYING" icon.color="$GREEN" label="$LABEL" drawing=on
