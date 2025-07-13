#!/bin/bash
# Clock Plugin for SketchyBar NG
# Shows time and date with AI-powered productivity insights

source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

# Get current time and date
CURRENT_TIME=$(date '+%H:%M')
CURRENT_DATE=$(date '+%m/%d')
DAY_OF_WEEK=$(date '+%a')
CURRENT_HOUR=$(date '+%H')

# Determine time period
if [[ $CURRENT_HOUR -ge 6 && $CURRENT_HOUR -lt 12 ]]; then
    TIME_PERIOD="morning"
    PERIOD_ICON="🌅"
elif [[ $CURRENT_HOUR -ge 12 && $CURRENT_HOUR -lt 17 ]]; then
    TIME_PERIOD="afternoon"
    PERIOD_ICON="☀️"
elif [[ $CURRENT_HOUR -ge 17 && $CURRENT_HOUR -lt 22 ]]; then
    TIME_PERIOD="evening"
    PERIOD_ICON="🌆"
else
    TIME_PERIOD="night"
    PERIOD_ICON="🌙"
fi

# Color based on time period
case $TIME_PERIOD in
    "morning")
        COLOR=$SUCCESS_COLOR
        ;;
    "afternoon")
        COLOR=$WARNING_COLOR
        ;;
    "evening")
        COLOR=$ACCENT_COLOR
        ;;
    "night")
        COLOR=$SECONDARY_COLOR
        ;;
esac

# AI-powered productivity insights
AI_PRODUCTIVITY_INSIGHTS() {
    # Only run AI analysis during work hours and if Ollama is available
    if [[ $CURRENT_HOUR -ge 9 && $CURRENT_HOUR -le 18 ]] && command -v ollama-manager &> /dev/null && ollama-manager status | grep -q "Service: Running"; then
        # Get current context
        CURRENT_APP=$(yabai -m query --windows --window | jq -r '.app' 2>/dev/null || echo "Unknown")
        UPTIME=$(uptime | awk '{print $3}' | sed 's/,//')
        BATTERY_LEVEL=$(pmset -g batt | grep -Eo "\d+%" | cut -d% -f1)
        
        # Determine work pattern
        WORK_PATTERN="unknown"
        if [[ $CURRENT_HOUR -ge 9 && $CURRENT_HOUR -le 12 ]]; then
            WORK_PATTERN="morning_focus"
        elif [[ $CURRENT_HOUR -ge 13 && $CURRENT_HOUR -le 15 ]]; then
            WORK_PATTERN="afternoon_work"
        elif [[ $CURRENT_HOUR -ge 16 && $CURRENT_HOUR -le 18 ]]; then
            WORK_PATTERN="evening_wrap"
        fi
        
        # Create context for AI analysis
        CONTEXT="Time: $CURRENT_TIME $DAY_OF_WEEK, period: $TIME_PERIOD, pattern: $WORK_PATTERN, app: $CURRENT_APP, uptime: $UPTIME, battery: $BATTERY_LEVEL%"
        
        # Ask AI for productivity tip (async, only run occasionally)
        if [[ $(( $(date +%s) % 600 )) -eq 0 ]]; then  # Every 10 minutes
            (
                AI_TIP=$(echo "Productivity context: $CONTEXT. Provide one brief productivity tip (6 words max):" | ollama-manager chat phi:2.7b | tail -1 2>/dev/null)
                
                if [[ -n "$AI_TIP" && "$AI_TIP" != *"error"* ]]; then
                    echo "$AI_TIP" > "/tmp/sketchybar_productivity_tip"
                fi
            ) &
        fi
    fi
}

# Run AI productivity insights (non-blocking)
AI_PRODUCTIVITY_INSIGHTS

# Check for stored AI tip
AI_TIP=""
if [[ -f "/tmp/sketchybar_productivity_tip" ]]; then
    AI_TIP=$(cat "/tmp/sketchybar_productivity_tip" 2>/dev/null || echo "")
    # Clean up old tips (older than 15 minutes)
    find /tmp -name "sketchybar_productivity_tip" -mmin +15 -delete 2>/dev/null
fi

# Meeting detection and reminders
MEETING_DETECTION() {
    # Check calendar events (if available)
    if command -v osascript &> /dev/null; then
        # Try to get next calendar event
        NEXT_EVENT=$(osascript -e 'tell application "Calendar" to get summary of (first event of (first calendar whose name is not "Subscriptions") whose start date > (current date))' 2>/dev/null || echo "")
        
        if [[ -n "$NEXT_EVENT" && "$NEXT_EVENT" != "missing value" ]]; then
            # Get event time
            EVENT_TIME=$(osascript -e 'tell application "Calendar" to get start date of (first event of (first calendar whose name is not "Subscriptions") whose start date > (current date))' 2>/dev/null || echo "")
            
            if [[ -n "$EVENT_TIME" ]]; then
                # Calculate time until event (simplified)
                CURRENT_TIMESTAMP=$(date +%s)
                # Note: This is a simplified check. Real implementation would parse EVENT_TIME properly
                echo "📅 Meeting soon" > "/tmp/sketchybar_meeting_reminder"
            fi
        fi
    fi
}

# Run meeting detection (occasionally)
if [[ $(( $(date +%s) % 300 )) -eq 0 ]]; then  # Every 5 minutes
    MEETING_DETECTION &
fi

# Work-life balance monitoring
WORK_BALANCE_CHECK() {
    WORK_HOURS_FILE="/tmp/sketchybar_work_hours"
    
    # Track work hours (simplified)
    if [[ $CURRENT_HOUR -ge 9 && $CURRENT_HOUR -le 18 ]]; then
        echo "$(date +%Y-%m-%d):work" >> "$WORK_HOURS_FILE"
    fi
    
    # Check for excessive work hours (simplified check)
    if [[ $CURRENT_HOUR -gt 20 ]]; then
        LATE_WORK_COUNT=$(grep "$(date +%Y-%m-%d)" "$WORK_HOURS_FILE" | wc -l)
        if [[ $LATE_WORK_COUNT -gt 50 ]]; then  # More than ~10 hours
            echo "Consider work-life balance" > "/tmp/sketchybar_balance_reminder"
        fi
    fi
    
    # Clean up old work hours data (keep only last 7 days)
    if [[ -f "$WORK_HOURS_FILE" ]]; then
        WEEK_AGO=$(date -d '7 days ago' '+%Y-%m-%d' 2>/dev/null || date -v-7d '+%Y-%m-%d')
        grep -v "$WEEK_AGO" "$WORK_HOURS_FILE" > "/tmp/work_temp" 2>/dev/null && mv "/tmp/work_temp" "$WORK_HOURS_FILE"
    fi
}

# Run work balance check
WORK_BALANCE_CHECK

# Break reminders
BREAK_REMINDERS() {
    # Simple break reminder every hour during work time
    if [[ $CURRENT_HOUR -ge 9 && $CURRENT_HOUR -le 18 ]] && [[ $(date '+%M') == "00" ]]; then
        if [[ $(( $(date +%s) % 3600 )) -lt 60 ]]; then  # Within first minute of hour
            echo "💧 Break time" > "/tmp/sketchybar_break_reminder"
        fi
    fi
}

# Run break reminders
BREAK_REMINDERS

# Build display label
LABEL="$CURRENT_TIME"

# Add date for wider displays or during specific times
if [[ $(( $(date +%s) % 30 )) -lt 15 ]]; then  # Show date half the time
    LABEL="$CURRENT_TIME $CURRENT_DATE"
fi

# Add day of week for weekend/monday
if [[ "$DAY_OF_WEEK" == "Mon" || "$DAY_OF_WEEK" == "Sat" || "$DAY_OF_WEEK" == "Sun" ]]; then
    LABEL="$DAY_OF_WEEK $LABEL"
fi

# Add period icon occasionally
if [[ $(( $(date +%s) % 60 )) -lt 10 ]]; then  # Show period icon for 10 seconds every minute
    LABEL="$PERIOD_ICON $LABEL"
fi

# Add AI productivity tip if available during work hours
if [[ -n "$AI_TIP" && $CURRENT_HOUR -ge 9 && $CURRENT_HOUR -le 18 ]]; then
    LABEL="$LABEL • $AI_TIP"
fi

# Add reminders if present
if [[ -f "/tmp/sketchybar_meeting_reminder" ]]; then
    MEETING_MSG=$(cat "/tmp/sketchybar_meeting_reminder")
    LABEL="$MEETING_MSG $LABEL"
    # Clean up old meeting reminders
    find /tmp -name "sketchybar_meeting_reminder" -mmin +30 -delete 2>/dev/null
fi

if [[ -f "/tmp/sketchybar_break_reminder" ]]; then
    BREAK_MSG=$(cat "/tmp/sketchybar_break_reminder")
    LABEL="$BREAK_MSG $LABEL"
    # Clean up break reminders after 5 minutes
    find /tmp -name "sketchybar_break_reminder" -mmin +5 -delete 2>/dev/null
fi

if [[ -f "/tmp/sketchybar_balance_reminder" ]]; then
    BALANCE_MSG=$(cat "/tmp/sketchybar_balance_reminder")
    LABEL="⚖️ $LABEL"
    # Clean up balance reminders after 1 hour
    find /tmp -name "sketchybar_balance_reminder" -mmin +60 -delete 2>/dev/null
fi

# Update SketchyBar
sketchybar --set $NAME icon="$LOADING" \
                   icon.color="$COLOR" \
                   label="$LABEL" \
                   label.color="$LABEL_COLOR"

# Special effects for certain times
case $CURRENT_TIME in
    "12:00"|"00:00")
        # Gentle pulse at noon and midnight
        sketchybar --animate sin 30 --set $NAME icon.color="$PRIMARY_COLOR"
        ;;
    *":00")
        # Subtle animation every hour
        if [[ $CURRENT_HOUR -ge 9 && $CURRENT_HOUR -le 18 ]]; then
            sketchybar --animate sin 15 --set $NAME icon.color="$ACCENT_COLOR"
        fi
        ;;
esac