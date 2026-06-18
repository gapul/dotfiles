#!/bin/bash

source "$CONFIG_DIR/colors.sh"

CORE_COUNT=$(sysctl -n machdep.cpu.thread_count)
CPU_INFO=$(ps -eo pcpu,user)
CPU_SYS=$(echo "$CPU_INFO" | grep -v $(whoami) | sed "s/[^ 0-9\.]//g" | awk "{sum+=\$1} END {print sum/(100.0 * $CORE_COUNT)}")
CPU_USER=$(echo "$CPU_INFO" | grep $(whoami) | sed "s/[^ 0-9\.]//g" | awk "{sum+=\$1} END {print sum/(100.0 * $CORE_COUNT)}")

CPU_PERCENT="$(echo "$CPU_SYS $CPU_USER" | awk '{printf "%.0f\n", ($1 + $2)*100}')"

if [ "$CPU_PERCENT" -lt 10 ]; then
  COLOR=$BLUE
elif [ "$CPU_PERCENT" -lt 30 ]; then
  COLOR=$GREEN
elif [ "$CPU_PERCENT" -lt 50 ]; then
  COLOR=$YELLOW
elif [ "$CPU_PERCENT" -lt 75 ]; then
  COLOR=$ORANGE
else
  COLOR=$RED
fi

sketchybar --set "$NAME" icon.color="$COLOR"
