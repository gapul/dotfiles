#!/bin/bash
# Space Plugin for SketchyBar NG
# Shows workspace/space information with AI-powered workspace optimization

source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

# Check if yabai is available
if ! command -v yabai &> /dev/null; then
    sketchybar --set $NAME drawing=off
    exit 0
fi

# Get current space information
SPACE_ID="$1"
CURRENT_SPACE=$(yabai -m query --spaces --space | jq -r '.index')
SPACE_INFO=$(yabai -m query --spaces --space "$SPACE_ID")

# Extract space details
SPACE_LABEL=$(echo "$SPACE_INFO" | jq -r '.label // empty')
SPACE_TYPE=$(echo "$SPACE_INFO" | jq -r '.type')
SPACE_WINDOWS=$(echo "$SPACE_INFO" | jq -r '.windows | length')
IS_FOCUSED=$(echo "$SPACE_INFO" | jq -r '.["has-focus"]')
IS_VISIBLE=$(echo "$SPACE_INFO" | jq -r '.["is-visible"]')

# Get window information for this space
WINDOWS_INFO=$(yabai -m query --windows --space "$SPACE_ID")
WINDOW_APPS=$(echo "$WINDOWS_INFO" | jq -r '.[].app' | sort -u)

# Determine space state and color
if [[ "$IS_FOCUSED" == "true" ]]; then
    STATE="focused"
    COLOR=$PRIMARY_COLOR
    BACKGROUND_COLOR=$ACCENT_COLOR
elif [[ "$IS_VISIBLE" == "true" ]]; then
    STATE="visible"
    COLOR=$SECONDARY_COLOR
    BACKGROUND_COLOR=$BACKGROUND_1
elif [[ $SPACE_WINDOWS -gt 0 ]]; then
    STATE="occupied"
    COLOR=$LABEL_COLOR
    BACKGROUND_COLOR=$BACKGROUND_2
else
    STATE="empty"
    COLOR=$GREY
    BACKGROUND_COLOR=$TRANSPARENT
fi

# Generate space icon based on primary app or space number
SPACE_ICON=""
if [[ $SPACE_WINDOWS -gt 0 ]]; then
    # Get most prominent app in space
    PRIMARY_APP=$(echo "$WINDOW_APPS" | head -1)
    
    case "$PRIMARY_APP" in
        "Arc"|"Safari"|"Google Chrome"|"Firefox"|"Microsoft Edge")
            SPACE_ICON="󰖟"
            ;;
        "Visual Studio Code"|"Cursor"|"Zed"|"Neovim"|"WebStorm"|"IntelliJ IDEA")
            SPACE_ICON="󰨞"
            ;;
        "Terminal"|"iTerm2"|"WezTerm"|"Alacritty")
            SPACE_ICON="󰆍"
            ;;
        "Finder")
            SPACE_ICON="󰉋"
            ;;
        "Spotify"|"Music"|"VLC"|"IINA")
            SPACE_ICON="󰎆"
            ;;
        "Discord"|"Slack"|"Microsoft Teams"|"Zoom")
            SPACE_ICON="󰭹"
            ;;
        "Figma"|"Sketch"|"Adobe Photoshop"|"Adobe Illustrator")
            SPACE_ICON="󰴹"
            ;;
        "Docker Desktop"|"Kubernetes Dashboard")
            SPACE_ICON="󰡨"
            ;;
        *)
            if [[ $SPACE_WINDOWS -eq 1 ]]; then
                SPACE_ICON="●"
            elif [[ $SPACE_WINDOWS -le 3 ]]; then
                SPACE_ICON="◉"
            else
                SPACE_ICON="⬢"
            fi
            ;;
    esac
else
    SPACE_ICON="○"
fi

# Use space label if available, otherwise use space number
if [[ -n "$SPACE_LABEL" && "$SPACE_LABEL" != "null" ]]; then
    DISPLAY_LABEL="$SPACE_LABEL"
else
    DISPLAY_LABEL="$SPACE_ID"
fi

# AI-powered workspace optimization
AI_WORKSPACE_OPTIMIZATION() {
    # Only run AI analysis for focused space and if Ollama is available
    if [[ "$IS_FOCUSED" == "true" ]] && [[ $SPACE_WINDOWS -gt 1 ]] && command -v ollama-manager &> /dev/null && ollama-manager status | grep -q "Service: Running"; then
        # Get window layout information
        LAYOUT_TYPE=$(echo "$SPACE_INFO" | jq -r '.type')
        
        # Get window arrangement details
        WINDOW_DETAILS=$(echo "$WINDOWS_INFO" | jq -r '.[] | .app + ":" + (.frame.w | tostring) + "x" + (.frame.h | tostring)')
        
        # Create context for AI analysis
        CONTEXT="Workspace $SPACE_ID: $SPACE_WINDOWS windows, layout: $LAYOUT_TYPE, apps: $(echo "$WINDOW_APPS" | tr '\n' ' '), focused: $IS_FOCUSED"
        
        # Ask AI for workspace optimization tip (async, run occasionally)
        if [[ $(( $(date +%s) % 600 )) -eq 0 ]]; then  # Every 10 minutes
            (
                AI_TIP=$(echo "Workspace context: $CONTEXT. Provide one brief workspace optimization tip (8 words max):" | ollama-manager chat phi:2.7b | tail -1 2>/dev/null)
                
                if [[ -n "$AI_TIP" && "$AI_TIP" != *"error"* ]]; then
                    echo "$AI_TIP" > "/tmp/sketchybar_workspace_tip_$SPACE_ID"
                fi
            ) &
        fi
    fi
}

# Run AI workspace optimization (non-blocking)
AI_WORKSPACE_OPTIMIZATION

# Check for stored AI tip for this space
AI_TIP=""
if [[ -f "/tmp/sketchybar_workspace_tip_$SPACE_ID" ]]; then
    AI_TIP=$(cat "/tmp/sketchybar_workspace_tip_$SPACE_ID" 2>/dev/null || echo "")
    # Clean up old tips (older than 20 minutes)
    find /tmp -name "sketchybar_workspace_tip_*" -mmin +20 -delete 2>/dev/null
fi

# Workspace productivity monitoring
PRODUCTIVITY_MONITORING() {
    # Track space usage patterns
    USAGE_FILE="/tmp/sketchybar_space_usage"
    
    if [[ "$IS_FOCUSED" == "true" ]]; then
        echo "$(date +%s):$SPACE_ID:$SPACE_WINDOWS:$(echo "$WINDOW_APPS" | head -1)" >> "$USAGE_FILE"
        
        # Keep only last 100 entries
        tail -100 "$USAGE_FILE" > "/tmp/usage_temp" 2>/dev/null && mv "/tmp/usage_temp" "$USAGE_FILE"
    fi
    
    # Detect workspace switching patterns
    if [[ -f "$USAGE_FILE" ]]; then
        RECENT_SWITCHES=$(tail -20 "$USAGE_FILE" | cut -d: -f2 | uniq | wc -l)
        
        # Alert for excessive workspace switching
        if [[ $RECENT_SWITCHES -gt 8 ]]; then
            echo "Frequent workspace switching" > "/tmp/sketchybar_workspace_alert"
        fi
    fi
}

# Run productivity monitoring
PRODUCTIVITY_MONITORING

# Window layout optimization suggestions
LAYOUT_OPTIMIZATION() {
    if [[ "$IS_FOCUSED" == "true" && $SPACE_WINDOWS -gt 3 ]]; then
        # Check for overcrowded workspace
        if [[ $SPACE_WINDOWS -gt 6 ]]; then
            echo "Consider organizing windows" > "/tmp/sketchybar_layout_suggestion_$SPACE_ID"
        fi
        
        # Check for similar apps in same space
        DUPLICATE_APPS=$(echo "$WINDOW_APPS" | sort | uniq -d | wc -l)
        if [[ $DUPLICATE_APPS -gt 1 ]]; then
            echo "Multiple similar apps detected" > "/tmp/sketchybar_app_organization_$SPACE_ID"
        fi
    fi
}

# Run layout optimization
LAYOUT_OPTIMIZATION

# Build display text
DISPLAY_TEXT="$DISPLAY_LABEL"

# Add window count indicator for occupied spaces
if [[ $SPACE_WINDOWS -gt 0 ]]; then
    if [[ $SPACE_WINDOWS -gt 1 ]]; then
        DISPLAY_TEXT="$DISPLAY_TEXT($SPACE_WINDOWS)"
    fi
fi

# Add productivity indicators
if [[ -f "/tmp/sketchybar_workspace_alert" ]]; then
    DISPLAY_TEXT="⚡ $DISPLAY_TEXT"
    # Clean up old alerts
    find /tmp -name "sketchybar_workspace_alert" -mmin +5 -delete 2>/dev/null
fi

if [[ -f "/tmp/sketchybar_layout_suggestion_$SPACE_ID" ]]; then
    DISPLAY_TEXT="🔀 $DISPLAY_TEXT"
    # Clean up old suggestions
    find /tmp -name "sketchybar_layout_suggestion_*" -mmin +15 -delete 2>/dev/null
fi

if [[ -f "/tmp/sketchybar_app_organization_$SPACE_ID" ]]; then
    DISPLAY_TEXT="📁 $DISPLAY_TEXT"
    # Clean up old organization suggestions
    find /tmp -name "sketchybar_app_organization_*" -mmin +10 -delete 2>/dev/null
fi

# Add AI tip if available and space is focused
if [[ -n "$AI_TIP" && "$IS_FOCUSED" == "true" ]]; then
    DISPLAY_TEXT="$DISPLAY_TEXT • $AI_TIP"
fi

# Update SketchyBar
sketchybar --set $NAME icon="$SPACE_ICON" \
                   icon.color="$COLOR" \
                   label="$DISPLAY_TEXT" \
                   label.color="$LABEL_COLOR" \
                   background.color="$BACKGROUND_COLOR" \
                   background.corner_radius=4 \
                   background.height=20

# Special animations for state changes
case $STATE in
    "focused")
        # Subtle pulse for focused space
        sketchybar --animate sin 20 --set $NAME background.color="$ACCENT_COLOR"
        ;;
    "visible")
        # Gentle fade for visible space
        sketchybar --animate sin 15 --set $NAME icon.color="$SECONDARY_COLOR"
        ;;
esac

# Handle space creation/destruction events
if [[ "$1" == "space_change" ]]; then
    # Refresh all space items when spaces change
    for i in {1..10}; do
        sketchybar --trigger space_change SPACE_ID="$i" &
    done
fi