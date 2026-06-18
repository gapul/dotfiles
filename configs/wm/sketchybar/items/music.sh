#!/bin/bash

# Set to "on" to hide the title/artist label by default and reveal it
# only when the play icon is clicked. Default is "off" (label always visible).
MUSIC_CLICK_TO_REVEAL="off"

if [ "$MUSIC_CLICK_TO_REVEAL" = "on" ]; then
  music_label_drawing="off"
  music_click_script="sketchybar --set music label.drawing=toggle"
else
  music_label_drawing="on"
  music_click_script=""
fi

music=(
  icon=$MUSIC_PLAYING
  icon.color=$GREEN
  icon.font="$FONT:Bold:14.0"
  label.font="$FONT:Semibold:13.0"
  label.color=$LABEL_COLOR
  label.max_chars=12
  label.shadow.drawing=off
  label.scroll_duration=150
  label.drawing=$music_label_drawing
  scroll_texts=on
  drawing=off
  updates=on
  update_freq=5
  script="$PLUGIN_DIR/music.sh"
  click_script="$music_click_script"
)

sketchybar --add item music right \
           --set music "${music[@]}"
