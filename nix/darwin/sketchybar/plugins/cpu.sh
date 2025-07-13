#!/bin/bash
# CPU Plugin for SketchyBar NG
# Shows CPU usage with AI-powered performance insights

source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

# Get CPU usage (average across all cores)
CPU_USAGE=$(top -l 1 | grep "CPU usage" | awk '{print $3}' | sed 's/%//')

# Handle empty CPU usage
if [[ -z "$CPU_USAGE" ]]; then
    CPU_USAGE="0"
fi

# Remove decimal point for comparison
CPU_INT=${CPU_USAGE%.*}

# Determine color based on CPU usage
if [[ $CPU_INT -ge 80 ]]; then
    COLOR=$ERROR_COLOR
    STATE="critical"
elif [[ $CPU_INT -ge 60 ]]; then
    COLOR=$WARNING_COLOR
    STATE="high"
elif [[ $CPU_INT -ge 30 ]]; then
    COLOR=$ACCENT_COLOR
    STATE="moderate"
else
    COLOR=$SUCCESS_COLOR
    STATE="low"
fi

# Get additional CPU information
CPU_INFO=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown CPU")
CORE_COUNT=$(sysctl -n hw.ncpu 2>/dev/null || echo "?")
THERMAL_STATE=$(pmset -g therm 2>/dev/null | grep -o "CPU_Speed_Limit.*" | head -1 || echo "Normal")

# Get top CPU consuming processes
TOP_PROCESSES=$(ps aux --sort=-%cpu | head -6 | tail -5 | awk '{print $11 " (" $3 "%)"}' | tr '\n' ' ')

# AI-powered performance analysis
AI_PERFORMANCE_CHECK() {
    # Only run AI analysis for high CPU usage and if Ollama is available
    if [[ $CPU_INT -ge 70 ]] && command -v ollama-manager &> /dev/null && ollama-manager status | grep -q "Service: Running"; then
        # Get current context
        CURRENT_HOUR=$(date +%H)
        UPTIME=$(uptime | awk '{print $3}' | sed 's/,//')
        LOAD_AVG=$(uptime | awk '{print $(NF-2)}' | sed 's/,//')
        
        # Create context for AI analysis
        CONTEXT="CPU: ${CPU_USAGE}%, cores: $CORE_COUNT, time: ${CURRENT_HOUR}:xx, uptime: $UPTIME, load: $LOAD_AVG, thermal: $THERMAL_STATE, top processes: $TOP_PROCESSES"
        
        # Ask AI for performance optimization tip (async)
        (
            AI_TIP=$(echo "Performance context: $CONTEXT. Provide one brief optimization tip (8 words max):" | ollama-manager chat phi:2.7b | tail -1 2>/dev/null)
            
            if [[ -n "$AI_TIP" && "$AI_TIP" != *"error"* ]]; then
                echo "$AI_TIP" > "/tmp/sketchybar_cpu_tip"
            fi
        ) &
    fi
}

# Run AI performance check (non-blocking)
AI_PERFORMANCE_CHECK

# Check for stored AI tip
AI_TIP=""
if [[ -f "/tmp/sketchybar_cpu_tip" ]]; then
    AI_TIP=$(cat "/tmp/sketchybar_cpu_tip" 2>/dev/null || echo "")
    # Clean up old tips (older than 3 minutes)
    find /tmp -name "sketchybar_cpu_tip" -mmin +3 -delete 2>/dev/null
fi

# Performance monitoring and alerts
PERFORMANCE_ALERT() {
    # Check for sustained high CPU usage
    HIGH_CPU_FILE="/tmp/sketchybar_high_cpu_count"
    
    if [[ $CPU_INT -ge 80 ]]; then
        # Increment high CPU counter
        if [[ -f "$HIGH_CPU_FILE" ]]; then
            COUNT=$(cat "$HIGH_CPU_FILE")
            COUNT=$((COUNT + 1))
        else
            COUNT=1
        fi
        echo "$COUNT" > "$HIGH_CPU_FILE"
        
        # Alert after 5 consecutive high CPU readings (10 seconds)
        if [[ $COUNT -ge 5 ]]; then
            # Check if we haven't alerted recently
            LAST_ALERT="/tmp/sketchybar_cpu_alert"
            if [[ ! -f "$LAST_ALERT" ]] || [[ $(find "$LAST_ALERT" -mmin +5) ]]; then
                # Send notification
                osascript -e "display notification \"Sustained high CPU usage: ${CPU_USAGE}%\" with title \"SketchyBar Performance Alert\""
                touch "$LAST_ALERT"
                
                # Log top processes for analysis
                echo "$(date): High CPU - $TOP_PROCESSES" >> "/tmp/sketchybar_performance.log"
            fi
        fi
    else
        # Reset counter for normal CPU usage
        rm -f "$HIGH_CPU_FILE" 2>/dev/null
    fi
}

# Run performance alert check
PERFORMANCE_ALERT

# Thermal throttling detection
THERMAL_CHECK() {
    if [[ "$THERMAL_STATE" == *"Speed_Limit"* ]]; then
        echo "🌡️ Thermal throttling" > "/tmp/sketchybar_thermal_warning"
    else
        rm -f "/tmp/sketchybar_thermal_warning" 2>/dev/null
    fi
}

# Run thermal check
THERMAL_CHECK

# Build label
LABEL="${CPU_USAGE}%"

# Add core count for high usage
if [[ $CPU_INT -ge 50 ]]; then
    LABEL="$LABEL (${CORE_COUNT}c)"
fi

# Add AI tip if available and CPU is high
if [[ -n "$AI_TIP" && $CPU_INT -ge 60 ]]; then
    LABEL="$LABEL • $AI_TIP"
fi

# Add thermal warning if present
if [[ -f "/tmp/sketchybar_thermal_warning" ]]; then
    THERMAL_MSG=$(cat "/tmp/sketchybar_thermal_warning")
    LABEL="$THERMAL_MSG $LABEL"
fi

# Update SketchyBar
sketchybar --set $NAME icon="$CPU" \
                   icon.color="$COLOR" \
                   label="$LABEL" \
                   label.color="$LABEL_COLOR"

# Special animations for critical states
case $STATE in
    "critical")
        # Pulse animation for critical CPU usage
        sketchybar --animate sin 20 --set $NAME icon.color="$ERROR_COLOR" &
        sleep 0.3
        sketchybar --animate sin 20 --set $NAME icon.color="$BACKGROUND_1" &
        ;;
    "high")
        # Gentle pulse for high CPU usage
        if [[ $(( $(date +%s) % 4 )) -eq 0 ]]; then
            sketchybar --animate sin 15 --set $NAME icon.color="$WARNING_COLOR"
        fi
        ;;
esac

# CPU history tracking (for trend analysis)
CPU_HISTORY_FILE="/tmp/sketchybar_cpu_history"
echo "$(date +%s):$CPU_USAGE" >> "$CPU_HISTORY_FILE"

# Keep only last 60 entries (2 minutes of history)
tail -60 "$CPU_HISTORY_FILE" > "/tmp/cpu_temp" && mv "/tmp/cpu_temp" "$CPU_HISTORY_FILE"