#!/bin/sh

volume_slider=(
  script="$PLUGIN_DIR/volume.sh"
  updates=on
  label.drawing=off
  icon.drawing=off
  padding_left=0
  padding_right=0
  slider.highlight_color=$BLUE
  slider.background.height=5
  slider.background.corner_radius=3
  slider.background.color=$BACKGROUND_2
  slider.knob=􀀁
  slider.knob.drawing=on
)

volume_icon=(
  click_script="$PLUGIN_DIR/volume_click.sh"
  script="$PLUGIN_DIR/volume_icon.sh"
  update_freq=5
  icon=$VOLUME_100
  icon.color=$GREY
  icon.font="$FONT:Bold:14.0"
  label.drawing=off
)

status_bracket=(
  background.color=$BACKGROUND_1
  background.border_color=$BACKGROUND_2
)

sketchybar --add slider volume right            \
           --set volume "${volume_slider[@]}"   \
           --subscribe volume volume_change     \
                              mouse.clicked     \
           --add item volume_icon right         \
           --set volume_icon "${volume_icon[@]}" \
           --subscribe volume_icon volume_change

sketchybar --add bracket status brew github.bell wifi volume_icon \
           --set status "${status_bracket[@]}"

# Seed initial volume state so the % label is populated on launch
INITIAL_VOLUME=$(osascript -e 'output volume of (get volume settings)' 2>/dev/null)
if [ -n "$INITIAL_VOLUME" ]; then
  sketchybar --trigger volume_change INFO=$INITIAL_VOLUME
fi

