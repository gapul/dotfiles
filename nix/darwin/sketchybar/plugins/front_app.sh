#!/bin/bash
# Front App Plugin for SketchyBar NG
# Shows the currently focused application

source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

# Get current front app
INFO="$(yabai -m query --windows --window)"

if [[ $INFO != "" ]]; then
    APP=$(echo $INFO | jq -r '.app')
    TITLE=$(echo $INFO | jq -r '.title')
    
    # Limit title length
    if [[ ${#TITLE} -gt 30 ]]; then
        TITLE="${TITLE:0:30}..."
    fi
    
    # Set app-specific icons and colors
    case $APP in
        "Arc"|"Safari"|"Google Chrome"|"Firefox"|"Microsoft Edge")
            ICON="󰖟"
            COLOR=$BLUE
            ;;
        "Visual Studio Code"|"Cursor"|"Zed"|"Neovim"|"WebStorm"|"IntelliJ IDEA")
            ICON="󰨞"
            COLOR=$GREEN
            ;;
        "Terminal"|"iTerm2"|"WezTerm"|"Alacritty")
            ICON="󰆍"
            COLOR=$ORANGE
            ;;
        "Finder")
            ICON="󰉋"
            COLOR=$BLUE
            ;;
        "Spotify"|"Music"|"VLC"|"IINA")
            ICON="󰎆"
            COLOR=$MAGENTA
            ;;
        "Discord"|"Slack"|"Microsoft Teams"|"Zoom")
            ICON="󰭹"
            COLOR=$SECONDARY_COLOR
            ;;
        "Figma"|"Sketch"|"Adobe Photoshop"|"Adobe Illustrator")
            ICON="󰴹"
            COLOR=$WARNING_COLOR
            ;;
        "Docker Desktop"|"Kubernetes Dashboard")
            ICON="󰡨"
            COLOR=$PRIMARY_COLOR
            ;;
        "System Preferences"|"System Settings")
            ICON="󰒓"
            COLOR=$GREY
            ;;
        *)
            ICON="󰘔"
            COLOR=$ACCENT_COLOR
            ;;
    esac
    
    # Check if app is in full screen
    IS_FULLSCREEN=$(echo $INFO | jq -r '.["has-fullscreen-zoom"]')
    
    if [[ $IS_FULLSCREEN == "true" ]]; then
        # In fullscreen, show minimal info
        sketchybar --set $NAME icon="$ICON" \
                             icon.color=$COLOR \
                             label="$APP" \
                             label.color=$LABEL_COLOR \
                             background.color=$TRANSPARENT
    else
        # Normal mode, show app and title
        if [[ $TITLE != "null" && $TITLE != "" ]]; then
            DISPLAY_TEXT="$APP • $TITLE"
        else
            DISPLAY_TEXT="$APP"
        fi
        
        sketchybar --set $NAME icon="$ICON" \
                             icon.color=$COLOR \
                             label="$DISPLAY_TEXT" \
                             label.color=$LABEL_COLOR \
                             background.color=$BACKGROUND_1
    fi
else
    # No active window
    sketchybar --set $NAME icon="󰘔" \
                         icon.color=$GREY \
                         label="Desktop" \
                         label.color=$LABEL_COLOR \
                         background.color=$TRANSPARENT
fi