#!/bin/bash

# Performance Monitoring Script
set -euo pipefail

METRICS_DIR="$HOME/.dotfiles/metrics"
mkdir -p "$METRICS_DIR"

# Generate timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# System metrics
{
    echo "=== System Performance Report - $(date) ==="
    echo ""
    
    echo "## Memory Usage"
    vm_stat | head -10
    echo ""
    
    echo "## Disk Usage"
    df -h | head -5
    echo ""
    
    echo "## Nix Store Size"
    if command -v nix >/dev/null 2>&1; then
        nix store optimise --dry-run 2>/dev/null | tail -3 || echo "Nix store analysis unavailable"
    fi
    echo ""
    
    echo "## Top Processes"
    ps aux | head -10
    echo ""
    
    echo "## Load Average"
    uptime
    echo ""
    
} > "$METRICS_DIR/performance-$TIMESTAMP.log"

# Keep only last 30 days of metrics
find "$METRICS_DIR" -name "performance-*.log" -mtime +30 -delete 2>/dev/null || true

echo "Performance metrics saved to: $METRICS_DIR/performance-$TIMESTAMP.log"
