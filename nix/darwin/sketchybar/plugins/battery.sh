#!/bin/bash
# Battery Plugin for SketchyBar NG
# Shows battery percentage and charging status with AI-powered optimization

source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

# Get battery information
BATTERY_INFO=$(pmset -g batt)
PERCENTAGE=$(echo "$BATTERY_INFO" | grep -Eo "\d+%" | cut -d% -f1)
CHARGING=$(echo "$BATTERY_INFO" | grep 'AC Power')

# Determine battery icon based on percentage
if [[ $PERCENTAGE -ge 75 ]]; then
    ICON=$BATTERY_100
    COLOR=$SUCCESS_COLOR
elif [[ $PERCENTAGE -ge 50 ]]; then
    ICON=$BATTERY_75
    COLOR=$ACCENT_COLOR
elif [[ $PERCENTAGE -ge 25 ]]; then
    ICON=$BATTERY_50
    COLOR=$WARNING_COLOR
elif [[ $PERCENTAGE -ge 10 ]]; then
    ICON=$BATTERY_25
    COLOR=$ERROR_COLOR
else
    ICON=$BATTERY_0
    COLOR=$ERROR_COLOR
fi

# Override icon if charging
if [[ $CHARGING != "" ]]; then
    ICON=$BATTERY_CHARGING
    COLOR=$SUCCESS_COLOR
fi

# Get time remaining
TIME_REMAINING=$(echo "$BATTERY_INFO" | grep -o '[0-9]*:[0-9]*' | head -1)

# AI-powered battery optimization notifications
AI_CHECK() {
    # Only run AI check if Ollama is available and percentage is critical
    if [[ $PERCENTAGE -le 15 ]] && command -v ollama-manager &> /dev/null && ollama-manager status | grep -q "Service: Running"; then
        # Get current context for AI analysis
        CURRENT_HOUR=$(date +%H)
        CURRENT_APP=$(yabai -m query --windows --window | jq -r '.app' 2>/dev/null || echo "Unknown")
        
        # Create context prompt for AI
        CONTEXT="Battery at ${PERCENTAGE}%, time: ${CURRENT_HOUR}:xx, current app: ${CURRENT_APP}, charging: ${CHARGING:+yes}${CHARGING:-no}"
        
        # Ask AI for battery optimization advice (async to avoid blocking UI)
        (
            AI_ADVICE=$(echo "Battery optimization context: $CONTEXT. Provide one brief battery saving tip (10 words max):" | ollama-manager chat phi:2.7b | tail -1 2>/dev/null)
            
            if [[ -n "$AI_ADVICE" && "$AI_ADVICE" != *"error"* ]]; then
                # Store AI advice for display
                echo "$AI_ADVICE" > "/tmp/sketchybar_battery_tip"
            fi
        ) &
    fi
}

# Run AI check (non-blocking)
AI_CHECK

# Check for stored AI tip
AI_TIP=""
if [[ -f "/tmp/sketchybar_battery_tip" ]]; then
    AI_TIP=$(cat "/tmp/sketchybar_battery_tip" 2>/dev/null || echo "")
    # Clean up old tips (older than 5 minutes)
    find /tmp -name "sketchybar_battery_tip" -mmin +5 -delete 2>/dev/null
fi

# Build label with optional AI tip
LABEL="$PERCENTAGE%"
if [[ $TIME_REMAINING != "" ]]; then
    LABEL="$LABEL ($TIME_REMAINING)"
fi

# Add AI tip if available and battery is low
if [[ -n "$AI_TIP" && $PERCENTAGE -le 20 ]]; then
    LABEL="$LABEL • $AI_TIP"
fi

# Battery health check (weekly)
HEALTH_CHECK() {
    LAST_HEALTH_CHECK="/tmp/battery_health_check"
    
    if [[ ! -f "$LAST_HEALTH_CHECK" ]] || [[ $(find "$LAST_HEALTH_CHECK" -mtime +7) ]]; then
        # Get battery health info
        BATTERY_HEALTH=$(system_profiler SPPowerDataType | grep -A5 "Condition" | grep -o "Normal\|Replace Soon\|Replace Now\|Service Battery" || echo "Unknown")
        CYCLE_COUNT=$(system_profiler SPPowerDataType | grep "Cycle Count" | awk '{print $3}' || echo "Unknown")
        
        # Store health info
        echo "Health: $BATTERY_HEALTH, Cycles: $CYCLE_COUNT" > "$LAST_HEALTH_CHECK"
        
        # Show notification for battery health issues
        if [[ "$BATTERY_HEALTH" != "Normal" && "$BATTERY_HEALTH" != "Unknown" ]]; then
            osascript -e "display notification \"Battery Health: $BATTERY_HEALTH (Cycles: $CYCLE_COUNT)\" with title \"SketchyBar Battery Alert\""
        fi
    fi
}

# Run health check (background)
HEALTH_CHECK &

# Update SketchyBar
sketchybar --set $NAME icon="$ICON" \
                   icon.color="$COLOR" \
                   label="$LABEL" \
                   label.color="$LABEL_COLOR"

# Special animations for critical battery
if [[ $PERCENTAGE -le 5 && $CHARGING == "" ]]; then
    # Blink animation for critical battery
    sketchybar --animate sin 30 --set $NAME icon.color="$ERROR_COLOR" &
    sleep 0.5
    sketchybar --animate sin 30 --set $NAME icon.color="$BACKGROUND_1" &
fi