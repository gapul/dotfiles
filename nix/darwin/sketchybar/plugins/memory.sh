#!/bin/bash
# Memory Plugin for SketchyBar NG
# Shows memory usage with AI-powered optimization insights

source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

# Get memory information using vm_stat
VM_STAT=$(vm_stat)

# Extract memory statistics (in pages)
PAGES_FREE=$(echo "$VM_STAT" | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
PAGES_ACTIVE=$(echo "$VM_STAT" | grep "Pages active" | awk '{print $3}' | sed 's/\.//')
PAGES_INACTIVE=$(echo "$VM_STAT" | grep "Pages inactive" | awk '{print $3}' | sed 's/\.//')
PAGES_SPECULATIVE=$(echo "$VM_STAT" | grep "Pages speculative" | awk '{print $3}' | sed 's/\.//')
PAGES_WIRED=$(echo "$VM_STAT" | grep "Pages wired down" | awk '{print $4}' | sed 's/\.//')
PAGES_COMPRESSED=$(echo "$VM_STAT" | grep "Pages stored in compressor" | awk '{print $5}' | sed 's/\.//')

# Get page size (typically 4KB on most systems)
PAGE_SIZE=$(pagesize)

# Calculate memory in MB
FREE_MB=$(( (PAGES_FREE * PAGE_SIZE) / 1024 / 1024 ))
ACTIVE_MB=$(( (PAGES_ACTIVE * PAGE_SIZE) / 1024 / 1024 ))
INACTIVE_MB=$(( (PAGES_INACTIVE * PAGE_SIZE) / 1024 / 1024 ))
WIRED_MB=$(( (PAGES_WIRED * PAGE_SIZE) / 1024 / 1024 ))
COMPRESSED_MB=$(( (PAGES_COMPRESSED * PAGE_SIZE) / 1024 / 1024 ))

# Calculate total and used memory
TOTAL_PHYSICAL=$(( $(sysctl -n hw.memsize) / 1024 / 1024 ))
USED_MB=$(( ACTIVE_MB + INACTIVE_MB + WIRED_MB + COMPRESSED_MB ))
AVAILABLE_MB=$(( FREE_MB + INACTIVE_MB ))

# Calculate memory usage percentage
MEMORY_USAGE=$(( (USED_MB * 100) / TOTAL_PHYSICAL ))

# Determine color based on memory usage
if [[ $MEMORY_USAGE -ge 90 ]]; then
    COLOR=$ERROR_COLOR
    STATE="critical"
elif [[ $MEMORY_USAGE -ge 75 ]]; then
    COLOR=$WARNING_COLOR
    STATE="high"
elif [[ $MEMORY_USAGE -ge 50 ]]; then
    COLOR=$ACCENT_COLOR
    STATE="moderate"
else
    COLOR=$SUCCESS_COLOR
    STATE="low"
fi

# Get memory pressure information
MEMORY_PRESSURE=$(memory_pressure)
PRESSURE_LEVEL="normal"

if echo "$MEMORY_PRESSURE" | grep -q "warn"; then
    PRESSURE_LEVEL="warn"
    COLOR=$WARNING_COLOR
elif echo "$MEMORY_PRESSURE" | grep -q "critical"; then
    PRESSURE_LEVEL="critical"
    COLOR=$ERROR_COLOR
fi

# Get top memory consuming processes
TOP_MEMORY_PROCESSES=$(ps aux --sort=-%mem | head -6 | tail -5 | awk '{print $11 " (" $4 "%)"}' | tr '\n' ' ')

# AI-powered memory optimization
AI_MEMORY_OPTIMIZATION() {
    # Only run AI analysis for high memory usage and if Ollama is available
    if [[ $MEMORY_USAGE -ge 75 ]] && command -v ollama-manager &> /dev/null && ollama-manager status | grep -q "Service: Running"; then
        # Get swap usage
        SWAP_USAGE=$(sysctl vm.swapusage 2>/dev/null | awk '{print $7}' | sed 's/M//' || echo "0")
        
        # Get current context
        CURRENT_HOUR=$(date +%H)
        UPTIME=$(uptime | awk '{print $3}' | sed 's/,//')
        
        # Create context for AI analysis
        CONTEXT="Memory: ${MEMORY_USAGE}% (${USED_MB}MB/${TOTAL_PHYSICAL}MB), pressure: $PRESSURE_LEVEL, swap: ${SWAP_USAGE}MB, time: ${CURRENT_HOUR}:xx, uptime: $UPTIME, top processes: $TOP_MEMORY_PROCESSES"
        
        # Ask AI for memory optimization tip (async)
        (
            AI_TIP=$(echo "Memory context: $CONTEXT. Provide one brief memory optimization tip (8 words max):" | ollama-manager chat phi:2.7b | tail -1 2>/dev/null)
            
            if [[ -n "$AI_TIP" && "$AI_TIP" != *"error"* ]]; then
                echo "$AI_TIP" > "/tmp/sketchybar_memory_tip"
            fi
        ) &
    fi
}

# Run AI memory optimization (non-blocking)
AI_MEMORY_OPTIMIZATION

# Check for stored AI tip
AI_TIP=""
if [[ -f "/tmp/sketchybar_memory_tip" ]]; then
    AI_TIP=$(cat "/tmp/sketchybar_memory_tip" 2>/dev/null || echo "")
    # Clean up old tips (older than 3 minutes)
    find /tmp -name "sketchybar_memory_tip" -mmin +3 -delete 2>/dev/null
fi

# Memory leak detection
MEMORY_LEAK_DETECTION() {
    HISTORY_FILE="/tmp/sketchybar_memory_history"
    
    # Record current memory usage
    echo "$(date +%s):$MEMORY_USAGE" >> "$HISTORY_FILE"
    
    # Keep only last 30 entries (1 minute of history)
    tail -30 "$HISTORY_FILE" > "/tmp/memory_temp" && mv "/tmp/memory_temp" "$HISTORY_FILE"
    
    # Check for consistent memory growth (leak detection)
    if [[ $(wc -l < "$HISTORY_FILE") -ge 20 ]]; then
        # Get first and last memory usage from history
        FIRST_USAGE=$(head -1 "$HISTORY_FILE" | cut -d: -f2)
        LAST_USAGE=$(tail -1 "$HISTORY_FILE" | cut -d: -f2)
        
        # Check if memory has consistently increased by more than 10%
        if [[ $((LAST_USAGE - FIRST_USAGE)) -gt 10 ]]; then
            echo "Potential memory leak detected" > "/tmp/sketchybar_memory_leak_warning"
        fi
    fi
}

# Run memory leak detection
MEMORY_LEAK_DETECTION

# Memory cleanup suggestions
CLEANUP_SUGGESTIONS() {
    # Check for high inactive memory that could be freed
    INACTIVE_PERCENTAGE=$(( (INACTIVE_MB * 100) / TOTAL_PHYSICAL ))
    
    if [[ $INACTIVE_PERCENTAGE -gt 20 && $MEMORY_USAGE -gt 70 ]]; then
        echo "Consider memory cleanup" > "/tmp/sketchybar_memory_cleanup"
    else
        rm -f "/tmp/sketchybar_memory_cleanup" 2>/dev/null
    fi
}

# Run cleanup suggestions
CLEANUP_SUGGESTIONS

# Memory pressure monitoring
PRESSURE_MONITORING() {
    if [[ "$PRESSURE_LEVEL" == "critical" ]]; then
        # Check if we haven't alerted recently
        LAST_ALERT="/tmp/sketchybar_memory_alert"
        if [[ ! -f "$LAST_ALERT" ]] || [[ $(find "$LAST_ALERT" -mmin +5) ]]; then
            # Send critical memory notification
            osascript -e "display notification \"Critical memory pressure: ${MEMORY_USAGE}%\" with title \"SketchyBar Memory Alert\""
            touch "$LAST_ALERT"
            
            # Log for analysis
            echo "$(date): Critical memory - $TOP_MEMORY_PROCESSES" >> "/tmp/sketchybar_memory.log"
        fi
    fi
}

# Run pressure monitoring
PRESSURE_MONITORING

# Build label
if [[ $TOTAL_PHYSICAL -gt 1024 ]]; then
    TOTAL_GB=$(( TOTAL_PHYSICAL / 1024 ))
    USED_GB=$(( USED_MB / 1024 ))
    LABEL="${MEMORY_USAGE}% (${USED_GB}/${TOTAL_GB}GB)"
else
    LABEL="${MEMORY_USAGE}% (${USED_MB}/${TOTAL_PHYSICAL}MB)"
fi

# Add pressure indicator
case $PRESSURE_LEVEL in
    "warn")
        LABEL="⚠️ $LABEL"
        ;;
    "critical")
        LABEL="🔴 $LABEL"
        ;;
esac

# Add AI tip if available and memory usage is high
if [[ -n "$AI_TIP" && $MEMORY_USAGE -ge 70 ]]; then
    LABEL="$LABEL • $AI_TIP"
fi

# Add cleanup suggestion if available
if [[ -f "/tmp/sketchybar_memory_cleanup" ]]; then
    CLEANUP_MSG=$(cat "/tmp/sketchybar_memory_cleanup")
    LABEL="🧹 $LABEL"
fi

# Add leak warning if detected
if [[ -f "/tmp/sketchybar_memory_leak_warning" ]]; then
    LABEL="🔍 $LABEL"
    # Clean up old leak warnings
    find /tmp -name "sketchybar_memory_leak_warning" -mmin +10 -delete 2>/dev/null
fi

# Update SketchyBar
sketchybar --set $NAME icon="$MEMORY" \
                   icon.color="$COLOR" \
                   label="$LABEL" \
                   label.color="$LABEL_COLOR"

# Special animations for critical states
case $STATE in
    "critical")
        # Pulse animation for critical memory usage
        sketchybar --animate sin 20 --set $NAME icon.color="$ERROR_COLOR" &
        sleep 0.3
        sketchybar --animate sin 20 --set $NAME icon.color="$BACKGROUND_1" &
        ;;
    "high")
        # Gentle pulse for high memory usage
        if [[ $(( $(date +%s) % 6 )) -eq 0 ]]; then
            sketchybar --animate sin 15 --set $NAME icon.color="$WARNING_COLOR"
        fi
        ;;
esac