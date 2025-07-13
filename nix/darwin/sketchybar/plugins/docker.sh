#!/bin/bash
# Docker Plugin for SketchyBar NG
# Shows Docker container status with AI-powered insights

source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    sketchybar --set $NAME drawing=off
    exit 0
fi

# Check if Docker daemon is running
if ! docker info &> /dev/null; then
    sketchybar --set $NAME icon="$DOCKER_STOPPED" \
                       icon.color="$GREY" \
                       label="Docker Off" \
                       label.color="$LABEL_COLOR" \
                       drawing=on
    exit 0
fi

# Get Docker container statistics
TOTAL_CONTAINERS=$(docker ps -a --format "table {{.Names}}" | tail -n +2 | wc -l | tr -d ' ')
RUNNING_CONTAINERS=$(docker ps --format "table {{.Names}}" | tail -n +2 | wc -l | tr -d ' ')
STOPPED_CONTAINERS=$((TOTAL_CONTAINERS - RUNNING_CONTAINERS))

# Get resource usage
DOCKER_STATS=$(docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null)

# Calculate total resource usage
TOTAL_CPU=0
TOTAL_MEMORY_MB=0
CONTAINER_COUNT=0

if [[ -n "$DOCKER_STATS" && "$DOCKER_STATS" != "CONTAINER"* ]]; then
    while IFS= read -r line; do
        if [[ "$line" == "CONTAINER"* ]]; then
            continue
        fi
        
        CPU_PERC=$(echo "$line" | awk '{print $2}' | sed 's/%//')
        MEMORY_RAW=$(echo "$line" | awk '{print $3}')
        
        # Extract memory in MB (handle different formats)
        if [[ "$MEMORY_RAW" == *"GiB"* ]]; then
            MEMORY_VAL=$(echo "$MEMORY_RAW" | sed 's/GiB.*//' | awk '{print $1}')
            MEMORY_MB=$(echo "$MEMORY_VAL * 1024" | bc 2>/dev/null || echo "0")
        elif [[ "$MEMORY_RAW" == *"MiB"* ]]; then
            MEMORY_MB=$(echo "$MEMORY_RAW" | sed 's/MiB.*//' | awk '{print $1}')
        else
            MEMORY_MB=0
        fi
        
        # Accumulate totals
        if [[ -n "$CPU_PERC" && "$CPU_PERC" != "" ]]; then
            TOTAL_CPU=$(echo "$TOTAL_CPU + $CPU_PERC" | bc 2>/dev/null || echo "$TOTAL_CPU")
        fi
        if [[ -n "$MEMORY_MB" && "$MEMORY_MB" != "" ]]; then
            TOTAL_MEMORY_MB=$(echo "$TOTAL_MEMORY_MB + $MEMORY_MB" | bc 2>/dev/null || echo "$TOTAL_MEMORY_MB")
        fi
        
        CONTAINER_COUNT=$((CONTAINER_COUNT + 1))
    done <<< "$DOCKER_STATS"
fi

# Determine status and color
if [[ $RUNNING_CONTAINERS -eq 0 ]]; then
    STATE="idle"
    COLOR=$GREY
    ICON=$DOCKER_STOPPED
elif [[ $RUNNING_CONTAINERS -le 3 ]]; then
    STATE="low"
    COLOR=$SUCCESS_COLOR
    ICON=$DOCKER_RUNNING
elif [[ $RUNNING_CONTAINERS -le 8 ]]; then
    STATE="moderate"
    COLOR=$WARNING_COLOR
    ICON=$DOCKER_RUNNING
else
    STATE="high"
    COLOR=$ERROR_COLOR
    ICON=$DOCKER_RUNNING
fi

# Get Docker system information
DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
DOCKER_IMAGES=$(docker images -q | wc -l | tr -d ' ')
DOCKER_VOLUMES=$(docker volume ls -q | wc -l | tr -d ' ')
DOCKER_NETWORKS=$(docker network ls --format "table {{.Name}}" | tail -n +2 | wc -l | tr -d ' ')

# Get container health status
UNHEALTHY_CONTAINERS=$(docker ps --filter "health=unhealthy" --format "{{.Names}}" | wc -l | tr -d ' ')

# AI-powered Docker optimization
AI_DOCKER_OPTIMIZATION() {
    # Only run AI analysis for active Docker usage and if Ollama is available
    if [[ $RUNNING_CONTAINERS -gt 0 ]] && command -v ollama-manager &> /dev/null && ollama-manager status | grep -q "Service: Running"; then
        # Get Docker disk usage
        DOCKER_DISK_USAGE=$(docker system df --format "table {{.Type}}\t{{.TotalCount}}\t{{.Size}}" 2>/dev/null)
        
        # Get resource-intensive containers
        TOP_CONTAINERS=$(docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" | head -4 | tail -3)
        
        # Create context for AI analysis
        CONTEXT="Docker: $RUNNING_CONTAINERS running, $STOPPED_CONTAINERS stopped, CPU: ${TOTAL_CPU}%, Memory: ${TOTAL_MEMORY_MB}MB, Images: $DOCKER_IMAGES, Volumes: $DOCKER_VOLUMES, Unhealthy: $UNHEALTHY_CONTAINERS"
        
        # Ask AI for optimization tip (async, run occasionally)
        if [[ $(( $(date +%s) % 300 )) -eq 0 ]]; then  # Every 5 minutes
            (
                AI_TIP=$(echo "Docker context: $CONTEXT. Provide one brief Docker optimization tip (8 words max):" | ollama-manager chat phi:2.7b | tail -1 2>/dev/null)
                
                if [[ -n "$AI_TIP" && "$AI_TIP" != *"error"* ]]; then
                    echo "$AI_TIP" > "/tmp/sketchybar_docker_tip"
                fi
            ) &
        fi
    fi
}

# Run AI Docker optimization (non-blocking)
AI_DOCKER_OPTIMIZATION

# Check for stored AI tip
AI_TIP=""
if [[ -f "/tmp/sketchybar_docker_tip" ]]; then
    AI_TIP=$(cat "/tmp/sketchybar_docker_tip" 2>/dev/null || echo "")
    # Clean up old tips (older than 10 minutes)
    find /tmp -name "sketchybar_docker_tip" -mmin +10 -delete 2>/dev/null
fi

# Docker health monitoring
DOCKER_HEALTH_CHECK() {
    # Check for resource-heavy containers
    if [[ $TOTAL_CPU -gt 200 ]]; then  # More than 200% total CPU
        echo "High CPU usage detected" > "/tmp/sketchybar_docker_cpu_warning"
    else
        rm -f "/tmp/sketchybar_docker_cpu_warning" 2>/dev/null
    fi
    
    # Check for memory usage
    if [[ $TOTAL_MEMORY_MB -gt 4096 ]]; then  # More than 4GB
        echo "High memory usage detected" > "/tmp/sketchybar_docker_memory_warning"
    else
        rm -f "/tmp/sketchybar_docker_memory_warning" 2>/dev/null
    fi
    
    # Check for unhealthy containers
    if [[ $UNHEALTHY_CONTAINERS -gt 0 ]]; then
        echo "$UNHEALTHY_CONTAINERS unhealthy container(s)" > "/tmp/sketchybar_docker_health_warning"
    else
        rm -f "/tmp/sketchybar_docker_health_warning" 2>/dev/null
    fi
    
    # Check for image cleanup needs
    DANGLING_IMAGES=$(docker images -f "dangling=true" -q | wc -l | tr -d ' ')
    if [[ $DANGLING_IMAGES -gt 10 ]]; then
        echo "Image cleanup needed" > "/tmp/sketchybar_docker_cleanup"
    else
        rm -f "/tmp/sketchybar_docker_cleanup" 2>/dev/null
    fi
}

# Run Docker health check
DOCKER_HEALTH_CHECK

# Container monitoring and alerts
CONTAINER_MONITORING() {
    # Check for containers that have been running for a very long time
    LONG_RUNNING=$(docker ps --format "table {{.Names}}\t{{.Status}}" | grep -c "months\|weeks" || echo "0")
    
    if [[ $LONG_RUNNING -gt 0 ]]; then
        echo "Long-running containers detected" > "/tmp/sketchybar_docker_longrun"
    else
        rm -f "/tmp/sketchybar_docker_longrun" 2>/dev/null
    fi
    
    # Check for containers with restart policies
    RESTART_CONTAINERS=$(docker ps --filter "status=restarting" --format "{{.Names}}" | wc -l | tr -d ' ')
    
    if [[ $RESTART_CONTAINERS -gt 0 ]]; then
        echo "$RESTART_CONTAINERS container(s) restarting" > "/tmp/sketchybar_docker_restart"
    else
        rm -f "/tmp/sketchybar_docker_restart" 2>/dev/null
    fi
}

# Run container monitoring
CONTAINER_MONITORING

# Build display label
if [[ $RUNNING_CONTAINERS -eq 0 ]]; then
    LABEL="Docker ($TOTAL_CONTAINERS)"
else
    LABEL="$RUNNING_CONTAINERS"
    
    # Add resource info for active containers
    if [[ $RUNNING_CONTAINERS -gt 0 ]]; then
        if [[ $TOTAL_CPU -gt 0 ]]; then
            LABEL="$LABEL (${TOTAL_CPU}%)"
        fi
        
        # Add memory if significant
        if [[ $TOTAL_MEMORY_MB -gt 512 ]]; then
            if [[ $TOTAL_MEMORY_MB -gt 1024 ]]; then
                MEMORY_GB=$(echo "scale=1; $TOTAL_MEMORY_MB / 1024" | bc)
                LABEL="$LABEL ${MEMORY_GB}GB"
            else
                LABEL="$LABEL ${TOTAL_MEMORY_MB}MB"
            fi
        fi
    fi
fi

# Add warnings and status indicators
WARNINGS=""

if [[ -f "/tmp/sketchybar_docker_health_warning" ]]; then
    WARNINGS="${WARNINGS}🏥"
fi

if [[ -f "/tmp/sketchybar_docker_cpu_warning" ]]; then
    WARNINGS="${WARNINGS}🔥"
fi

if [[ -f "/tmp/sketchybar_docker_memory_warning" ]]; then
    WARNINGS="${WARNINGS}💾"
fi

if [[ -f "/tmp/sketchybar_docker_cleanup" ]]; then
    WARNINGS="${WARNINGS}🧹"
fi

if [[ -f "/tmp/sketchybar_docker_longrun" ]]; then
    WARNINGS="${WARNINGS}⏰"
fi

if [[ -f "/tmp/sketchybar_docker_restart" ]]; then
    WARNINGS="${WARNINGS}🔄"
fi

# Add warnings to label
if [[ -n "$WARNINGS" ]]; then
    LABEL="$WARNINGS $LABEL"
fi

# Add AI tip if available and Docker is active
if [[ -n "$AI_TIP" && $RUNNING_CONTAINERS -gt 0 ]]; then
    LABEL="$LABEL • $AI_TIP"
fi

# Update SketchyBar
sketchybar --set $NAME icon="$ICON" \
                   icon.color="$COLOR" \
                   label="$LABEL" \
                   label.color="$LABEL_COLOR" \
                   drawing=on

# Special animations for different states
case $STATE in
    "high")
        # Pulse animation for high container count
        if [[ $(( $(date +%s) % 8 )) -eq 0 ]]; then
            sketchybar --animate sin 20 --set $NAME icon.color="$ERROR_COLOR"
        fi
        ;;
    "moderate")
        # Gentle pulse for moderate usage
        if [[ $(( $(date +%s) % 12 )) -eq 0 ]]; then
            sketchybar --animate sin 15 --set $NAME icon.color="$WARNING_COLOR"
        fi
        ;;
esac

# Quick cleanup suggestion (run occasionally)
if [[ $(( $(date +%s) % 1800 )) -eq 0 ]] && [[ $RUNNING_CONTAINERS -gt 5 ]]; then
    # Suggest cleanup if many containers
    osascript -e "display notification \"Consider Docker cleanup: docker system prune\" with title \"SketchyBar Docker Tip\"" &
fi