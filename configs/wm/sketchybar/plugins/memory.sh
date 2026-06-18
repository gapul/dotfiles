#!/bin/bash

source "$CONFIG_DIR/colors.sh"

PAGE_SIZE=$(sysctl -n hw.pagesize)
TOTAL_BYTES=$(sysctl -n hw.memsize)

VM=$(vm_stat)
ACTIVE=$(echo "$VM"     | awk '/Pages active:/                {gsub(/\./,"",$NF); print $NF}')
WIRED=$(echo "$VM"      | awk '/Pages wired down:/            {gsub(/\./,"",$NF); print $NF}')
COMPRESSED=$(echo "$VM" | awk '/Pages occupied by compressor:/{gsub(/\./,"",$NF); print $NF}')

USED_BYTES=$(( (ACTIVE + WIRED + COMPRESSED) * PAGE_SIZE ))
MEM_PERCENT=$(( USED_BYTES * 100 / TOTAL_BYTES ))

if [ "$MEM_PERCENT" -lt 40 ]; then
  COLOR=$BLUE
elif [ "$MEM_PERCENT" -lt 60 ]; then
  COLOR=$GREEN
elif [ "$MEM_PERCENT" -lt 75 ]; then
  COLOR=$YELLOW
elif [ "$MEM_PERCENT" -lt 90 ]; then
  COLOR=$ORANGE
else
  COLOR=$RED
fi

sketchybar --set "$NAME" icon.color="$COLOR"
