#!/bin/bash

# Dynamic Island SketchyBar Launcher
# This script starts Dynamic Island as a secondary bar

export DYNAMIC_ISLAND_DIR="/opt/homebrew/etc/dynamic-island-sketchybar"

# Load user config
source "$HOME/.config/dynamic-island-sketchybar/userconfig.sh"

# Start Dynamic Island bar
exec /opt/homebrew/bin/sketchybar -c "$DYNAMIC_ISLAND_DIR/sketchybarrc"