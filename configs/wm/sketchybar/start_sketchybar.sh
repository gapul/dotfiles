#!/bin/bash

# SketchyBar Startup Script
# Enhanced startup script with error handling and dependency checking

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${CONFIG_DIR:-$SCRIPT_DIR}"
SKETCHYBAR_RC="$CONFIG_DIR/sketchybarrc"
LOG_FILE="${HOME}/.sketchybar/sketchybar.log"
PID_FILE="/tmp/sketchybar_$USER.pid"

# Logging functions
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "$LOG_FILE" >&2
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $*" | tee -a "$LOG_FILE"
}

# Create log directory
mkdir -p "$(dirname "$LOG_FILE")"

# Cleanup function
cleanup() {
    if [[ -f "$PID_FILE" ]]; then
        rm -f "$PID_FILE"
    fi
}

trap cleanup EXIT

# Check dependencies
check_dependencies() {
    log_info "Checking dependencies..."
    
    local missing_deps=()
    
    # Check for required commands
    for cmd in sketchybar lua make; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    # Check for configuration files
    if [[ ! -f "$SKETCHYBAR_RC" ]]; then
        missing_deps+=("$SKETCHYBAR_RC")
    fi
    
    if [[ ! -d "$CONFIG_DIR/helpers" ]]; then
        missing_deps+=("helpers directory")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        return 1
    fi
    
    log_info "All dependencies satisfied"
    return 0
}

# Stop existing SketchyBar instances
stop_sketchybar() {
    log_info "Stopping existing SketchyBar instances..."
    
    # Try graceful shutdown first
    if pgrep -x sketchybar >/dev/null; then
        log_info "Found running SketchyBar, stopping..."
        pkill -TERM sketchybar 2>/dev/null || true
        sleep 2
    fi
    
    # Force kill if still running
    if pgrep -x sketchybar >/dev/null; then
        log_warn "Force killing SketchyBar..."
        pkill -KILL sketchybar 2>/dev/null || true
        sleep 1
    fi
    
    # Clean up lock files
    rm -f /tmp/sketchybar_* 2>/dev/null || true
    
    # Remove from launchctl if present
    launchctl remove com.felixkratz.sketchybar 2>/dev/null || true
    
    log_info "SketchyBar stopped"
}

# Build helpers if needed
build_helpers() {
    log_info "Building helper binaries..."
    
    local helpers_dir="$CONFIG_DIR/helpers"
    if [[ ! -f "$helpers_dir/makefile" ]] && [[ ! -f "$helpers_dir/Makefile" ]]; then
        log_error "No makefile found in helpers directory"
        return 1
    fi
    
    # Build helpers
    if ! (cd "$helpers_dir" && make >/dev/null 2>&1); then
        log_error "Failed to build helper binaries"
        return 1
    fi
    
    # Verify critical binaries
    local cpu_binary="$helpers_dir/event_providers/cpu_load/bin/cpu_load"
    local network_binary="$helpers_dir/event_providers/network_load/bin/network_load"
    
    if [[ -x "$cpu_binary" ]] && [[ -x "$network_binary" ]]; then
        log_info "Helper binaries built and verified successfully"
        return 0
    else
        log_error "Helper binaries missing or not executable"
        return 1
    fi
}

# Start SketchyBar
start_sketchybar() {
    log_info "Starting SketchyBar..."
    
    # Set environment variables
    export CONFIG_DIR="$CONFIG_DIR"
    
    # Start SketchyBar with proper error handling
    "$SKETCHYBAR_RC" >/dev/null 2>&1 &
    local start_result=$?
    if [[ $start_result -ne 0 ]]; then
        log_error "Failed to start SketchyBar"
        return 1
    fi
    
    local sketchybar_pid=$!
    echo "$sketchybar_pid" > "$PID_FILE"
    
    # Wait a moment and check if it's still running
    sleep 2
    if ! kill -0 "$sketchybar_pid" 2>/dev/null; then
        log_error "SketchyBar exited immediately"
        return 1
    fi
    
    log_info "SketchyBar started successfully (PID: $sketchybar_pid)"
    return 0
}

# Main execution
main() {
    log_info "Starting SketchyBar initialization..."
    
    # Check dependencies
    if ! check_dependencies; then
        log_error "Dependency check failed"
        exit 1
    fi
    
    # Stop any existing instances
    stop_sketchybar
    
    # Build helpers if needed
    if ! build_helpers; then
        log_error "Helper build failed"
        exit 1
    fi
    
    # Start SketchyBar
    if ! start_sketchybar; then
        log_error "SketchyBar startup failed"
        exit 1
    fi
    
    log_info "SketchyBar initialization completed successfully"
}

# Handle script arguments
case "${1:-start}" in
    start)
        main
        ;;
    stop)
        stop_sketchybar
        ;;
    restart)
        stop_sketchybar
        sleep 1
        main
        ;;
    status)
        if pgrep -x sketchybar >/dev/null; then
            echo "SketchyBar is running"
            exit 0
        else
            echo "SketchyBar is not running"
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac