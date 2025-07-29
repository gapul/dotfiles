#!/usr/bin/env bash

# Performance Monitor - Real-time system performance monitoring
# Provides comprehensive performance metrics and analysis

set -euo pipefail

# Colors and icons
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

CHART="📊"
COMPUTER="💻"
MEMORY="💾"
DISK="💽"
NETWORK="🌐"
CLOCK="⏱️"
FIRE="🔥"
SNOWFLAKE="❄️"
WARNING="⚠️"
CHECK="✅"

# Performance thresholds
CPU_WARNING_THRESHOLD=70
CPU_CRITICAL_THRESHOLD=90
MEMORY_WARNING_THRESHOLD=75
MEMORY_CRITICAL_THRESHOLD=90
DISK_WARNING_THRESHOLD=80
DISK_CRITICAL_THRESHOLD=95

# Logging function
log_metric() {
    local icon="$1"
    local label="$2"
    local value="$3"
    local threshold="$4"
    local unit="${5:-%}"
    
    printf "%-20s %s %-25s" "$icon $label:" "" "$value$unit"
    
    if [[ ${value%.*} -ge $threshold ]]; then
        echo -e " ${RED}${WARNING}${NC}"
    elif [[ ${value%.*} -ge $((threshold - 20)) ]]; then
        echo -e " ${YELLOW}${WARNING}${NC}"
    else
        echo -e " ${GREEN}${CHECK}${NC}"
    fi
}

# Get CPU usage (macOS)
get_cpu_usage() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS CPU usage
        top -l 1 | grep "CPU usage" | awk '{print $3}' | sed 's/%//' || echo "0"
    else
        # Linux CPU usage
        grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {print usage}' || echo "0"
    fi
}

# Get memory usage (macOS)
get_memory_usage() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS memory usage via vm_stat
        vm_stat | awk '
            /Pages free:/ {free = $3}
            /Pages active:/ {active = $3}
            /Pages inactive:/ {inactive = $3}
            /Pages wired down:/ {wired = $4}
            /Pages occupied by compressor:/ {compressed = $5}
            END {
                total = free + active + inactive + wired + compressed
                used = active + inactive + wired + compressed
                if (total > 0) {
                    usage = used * 100 / total
                    print int(usage)
                } else {
                    print 0
                }
            }'
    else
        # Linux memory usage
        free | awk 'NR==2{printf "%.0f", $3*100/$2}' || echo "0"
    fi
}

# Get disk usage
get_disk_usage() {
    df -h / | awk 'NR==2 {print $5}' | sed 's/%//' || echo "0"
}

# Get system load
get_system_load() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sysctl -n vm.loadavg | awk '{print $2}' || echo "0.0"
    else
        uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//' || echo "0.0"
    fi
}

# Get process count
get_process_count() {
    ps aux | wc -l | tr -d ' ' || echo "0"
}

# Get network connections
get_network_connections() {
    if command -v lsof &>/dev/null; then
        lsof -i | wc -l | tr -d ' ' || echo "0"
    else
        netstat -an 2>/dev/null | wc -l | tr -d ' ' || echo "0"
    fi
}

# Get Nix store size
get_nix_store_size() {
    if [[ -d "/nix/store" ]]; then
        du -sh /nix/store 2>/dev/null | cut -f1 | sed 's/[^0-9.]//g' || echo "0"
    else
        echo "0"
    fi
}

# Get temperature (macOS)
get_temperature() {
    if [[ "$OSTYPE" == "darwin"* ]] && command -v osx-cpu-temp &>/dev/null; then
        osx-cpu-temp | sed 's/°C//' || echo "N/A"
    else
        echo "N/A"
    fi
}

# Get uptime
get_uptime() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        uptime | awk '{print $3, $4}' | sed 's/,//' || echo "unknown"
    else
        uptime -p | sed 's/up //' || echo "unknown"
    fi
}

# Get top processes by CPU
get_top_cpu_processes() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        ps aux | sort -nr -k 3 | head -5 | awk '{printf "  %-20s %5.1f%%\n", $11, $3}'
    else
        ps aux | sort -nr -k 3 | head -5 | awk '{printf "  %-20s %5.1f%%\n", $11, $3}'
    fi
}

# Get top processes by memory
get_top_memory_processes() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        ps aux | sort -nr -k 4 | head -5 | awk '{printf "  %-20s %5.1f%%\n", $11, $4}'
    else
        ps aux | sort -nr -k 4 | head -5 | awk '{printf "  %-20s %5.1f%%\n", $11, $4}'
    fi
}

# Performance analysis
analyze_performance() {
    local cpu_usage="$1"
    local memory_usage="$2"
    local disk_usage="$3"
    local load_avg="$4"
    
    echo ""
    echo -e "${BLUE}🔍 Performance Analysis:${NC}"
    echo "────────────────────────────"
    
    # Overall system health
    local issues=0
    
    if [[ ${cpu_usage%.*} -ge $CPU_CRITICAL_THRESHOLD ]]; then
        echo -e "${RED}${FIRE} Critical: Very high CPU usage detected${NC}"
        echo "  Recommendation: Check top CPU processes and consider optimization"
        issues=$((issues + 1))
    elif [[ ${cpu_usage%.*} -ge $CPU_WARNING_THRESHOLD ]]; then
        echo -e "${YELLOW}${WARNING} Warning: High CPU usage detected${NC}"
        echo "  Recommendation: Monitor CPU-intensive processes"
        issues=$((issues + 1))
    fi
    
    if [[ ${memory_usage%.*} -ge $MEMORY_CRITICAL_THRESHOLD ]]; then
        echo -e "${RED}${FIRE} Critical: Very high memory usage detected${NC}"
        echo "  Recommendation: Close unnecessary applications or add more RAM"
        issues=$((issues + 1))
    elif [[ ${memory_usage%.*} -ge $MEMORY_WARNING_THRESHOLD ]]; then
        echo -e "${YELLOW}${WARNING} Warning: High memory usage detected${NC}"
        echo "  Recommendation: Monitor memory-intensive processes"
        issues=$((issues + 1))
    fi
    
    if [[ ${disk_usage%.*} -ge $DISK_CRITICAL_THRESHOLD ]]; then
        echo -e "${RED}${FIRE} Critical: Very high disk usage detected${NC}"
        echo "  Recommendation: Free up disk space immediately"
        echo "  • Run 'nix-collect-garbage -d' to clean Nix store"
        echo "  • Run 'system-maintenance' for general cleanup"
        issues=$((issues + 1))
    elif [[ ${disk_usage%.*} -ge $DISK_WARNING_THRESHOLD ]]; then
        echo -e "${YELLOW}${WARNING} Warning: High disk usage detected${NC}"
        echo "  Recommendation: Consider cleaning up unnecessary files"
        issues=$((issues + 1))
    fi
    
    # Load average analysis
    local load_threshold=$(sysctl -n hw.ncpu 2>/dev/null || echo "4")
    if (( $(echo "$load_avg > $load_threshold" | bc -l 2>/dev/null || echo "0") )); then
        echo -e "${YELLOW}${WARNING} High system load detected${NC}"
        echo "  Current load: $load_avg (recommended: < $load_threshold)"
        issues=$((issues + 1))
    fi
    
    if [[ $issues -eq 0 ]]; then
        echo -e "${GREEN}${CHECK} System performance is optimal${NC}"
        echo "  All metrics are within healthy ranges"
    fi
    
    echo ""
}

# Generate performance recommendations
generate_recommendations() {
    echo -e "${BLUE}💡 Performance Recommendations:${NC}"
    echo "─────────────────────────────────"
    
    # General recommendations
    echo "Regular Maintenance:"
    echo "  • Run 'system-maintenance' weekly"
    echo "  • Monitor disk space regularly"
    echo "  • Keep system updated"
    echo ""
    
    echo "Performance Optimization:"
    echo "  • Use modern CLI tools (eza, bat, rg, fd)"
    echo "  • Enable shell completion caching"
    echo "  • Consider SSD for better I/O performance"
    echo ""
    
    echo "Monitoring:"
    echo "  • Set up automated alerts for critical thresholds"
    echo "  • Monitor during peak usage times"
    echo "  • Keep performance logs for trend analysis"
    echo ""
}

# Real-time monitoring mode
real_time_monitor() {
    local interval="${1:-5}"
    local duration="${2:-60}"
    local iterations=$((duration / interval))
    
    echo -e "${BLUE}🔄 Real-time Performance Monitor${NC}"
    echo "Monitoring for $duration seconds (refresh every ${interval}s)"
    echo "Press Ctrl+C to stop"
    echo ""
    
    for ((i=1; i<=iterations; i++)); do
        clear
        echo -e "${BLUE}Real-time Monitor - Sample $i/$iterations${NC}"
        echo "$(date)"
        echo ""
        
        main_monitor
        
        if [[ $i -lt $iterations ]]; then
            sleep "$interval"
        fi
    done
}

# Main monitoring function
main_monitor() {
    echo -e "${BLUE}${CHART} System Performance Monitor${NC}"
    echo "════════════════════════════════"
    echo ""
    
    # Get all metrics
    local cpu_usage
    cpu_usage=$(get_cpu_usage)
    local memory_usage
    memory_usage=$(get_memory_usage)
    local disk_usage
    disk_usage=$(get_disk_usage)
    local load_avg
    load_avg=$(get_system_load)
    local process_count
    process_count=$(get_process_count)
    local network_connections
    network_connections=$(get_network_connections)
    local nix_store_size
    nix_store_size=$(get_nix_store_size)
    local temperature
    temperature=$(get_temperature)
    local uptime
    uptime=$(get_uptime)
    
    # Display system information
    echo -e "${BLUE}📋 System Information:${NC}"
    echo "────────────────────────"
    echo "  OS: $(uname -s) $(uname -r)"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "  macOS: $(sw_vers -productVersion)"
        echo "  Hardware: $(uname -m)"
    fi
    echo "  Uptime: $uptime"
    echo "  Processes: $process_count"
    echo "  Network Connections: $network_connections"
    echo ""
    
    # Display main metrics
    echo -e "${BLUE}🎯 Performance Metrics:${NC}"
    echo "─────────────────────────"
    log_metric "$COMPUTER" "CPU Usage" "$cpu_usage" "$CPU_WARNING_THRESHOLD"
    log_metric "$MEMORY" "Memory Usage" "$memory_usage" "$MEMORY_WARNING_THRESHOLD"
    log_metric "$DISK" "Disk Usage" "$disk_usage" "$DISK_WARNING_THRESHOLD"
    log_metric "$CLOCK" "Load Average" "$load_avg" "4" ""
    
    if [[ "$temperature" != "N/A" ]]; then
        log_metric "🌡️" "CPU Temperature" "$temperature" "70" "°C"
    fi
    
    echo ""
    
    # Nix-specific metrics
    echo -e "${BLUE}📦 Nix Performance:${NC}"
    echo "──────────────────────"
    echo "  Nix Store Size: ${nix_store_size}GB"
    
    if command -v nix &>/dev/null; then
        local nix_version
        nix_version=$(nix --version | head -1)
        echo "  Nix Version: $nix_version"
    fi
    
    # Check for recent Nix operations
    if [[ -f "$HOME/.nix-profile/manifest.json" ]]; then
        local last_install
        last_install=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$HOME/.nix-profile/manifest.json" 2>/dev/null || echo "unknown")
        echo "  Last Profile Update: $last_install"
    fi
    
    echo ""
    
    # Top processes
    echo -e "${BLUE}🔝 Top CPU Processes:${NC}"
    echo "───────────────────────"
    get_top_cpu_processes
    echo ""
    
    echo -e "${BLUE}💾 Top Memory Processes:${NC}"
    echo "─────────────────────────"
    get_top_memory_processes
    echo ""
    
    # Performance analysis
    analyze_performance "$cpu_usage" "$memory_usage" "$disk_usage" "$load_avg"
    
    # Save performance data for history
    local perf_log="$HOME/.dotfiles-health/performance-history.log"
    mkdir -p "$(dirname "$perf_log")"
    echo "$(date -Iseconds),$cpu_usage,$memory_usage,$disk_usage,$load_avg" >> "$perf_log"
}

# Show performance history
show_performance_history() {
    local days="${1:-7}"
    local perf_log="$HOME/.dotfiles-health/performance-history.log"
    
    if [[ ! -f "$perf_log" ]]; then
        echo "No performance history available yet."
        echo "Run performance-monitor regularly to build history."
        return 1
    fi
    
    echo -e "${BLUE}📈 Performance History (Last $days days):${NC}"
    echo "════════════════════════════════════════"
    echo ""
    
    # Show recent entries
    local cutoff_date
    if [[ "$OSTYPE" == "darwin"* ]]; then
        cutoff_date=$(date -v-${days}d -Iseconds)
    else
        cutoff_date=$(date -d "$days days ago" -Iseconds)
    fi
    
    awk -F',' -v cutoff="$cutoff_date" '
    $1 >= cutoff {
        printf "%-20s CPU: %5.1f%% MEM: %5.1f%% DISK: %5.1f%% LOAD: %5.2f\n", 
               $1, $2, $3, $4, $5
    }' "$perf_log" | tail -20
    
    echo ""
    
    # Calculate averages
    local avg_cpu avg_memory avg_disk
    avg_cpu=$(awk -F',' -v cutoff="$cutoff_date" '$1 >= cutoff {sum+=$2; count++} END {if(count>0) printf "%.1f", sum/count; else print "0"}' "$perf_log")
    avg_memory=$(awk -F',' -v cutoff="$cutoff_date" '$1 >= cutoff {sum+=$3; count++} END {if(count>0) printf "%.1f", sum/count; else print "0"}' "$perf_log")
    avg_disk=$(awk -F',' -v cutoff="$cutoff_date" '$1 >= cutoff {sum+=$4; count++} END {if(count>0) printf "%.1f", sum/count; else print "0"}' "$perf_log")
    
    echo "Average Performance (Last $days days):"
    echo "  CPU: ${avg_cpu}%"
    echo "  Memory: ${avg_memory}%"
    echo "  Disk: ${avg_disk}%"
    echo ""
}

# Help function
show_help() {
    cat << EOF
Performance Monitor - System Performance Analysis

USAGE:
    $(basename "$0") [OPTIONS]

DESCRIPTION:
    Monitors and analyzes system performance with real-time metrics,
    historical data, and optimization recommendations.

OPTIONS:
    -h, --help              Show this help message
    -r, --real-time [SEC]   Real-time monitoring mode (default: 5s intervals)
    -d, --duration SEC      Duration for real-time mode (default: 60s)
    -H, --history [DAYS]    Show performance history (default: 7 days)
    --recommendations       Show performance optimization recommendations
    --json                  Output in JSON format

EXAMPLES:
    $(basename "$0")                    # One-time performance check
    $(basename "$0") --real-time        # Real-time monitoring
    $(basename "$0") --real-time 2      # Real-time with 2s intervals
    $(basename "$0") --history 14       # Show 14-day history
    $(basename "$0") --recommendations  # Get optimization tips

METRICS MONITORED:
    • CPU usage and load average
    • Memory utilization
    • Disk space usage
    • System temperature (if available)
    • Process counts and top consumers
    • Nix store size and operations

RELATED COMMANDS:
    system-health-master            # Overall system health
    system-maintenance              # Performance optimization

EOF
}

# Parse command line arguments
REAL_TIME=false
DURATION=60
INTERVAL=5
SHOW_HISTORY=false
HISTORY_DAYS=7
SHOW_RECOMMENDATIONS=false
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -r|--real-time)
            REAL_TIME=true
            if [[ -n "${2:-}" && "$2" =~ ^[0-9]+$ ]]; then
                INTERVAL="$2"
                shift
            fi
            shift
            ;;
        -d|--duration)
            DURATION="$2"
            shift 2
            ;;
        -H|--history)
            SHOW_HISTORY=true
            if [[ -n "${2:-}" && "$2" =~ ^[0-9]+$ ]]; then
                HISTORY_DAYS="$2"
                shift
            fi
            shift
            ;;
        --recommendations)
            SHOW_RECOMMENDATIONS=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Main execution
if [[ "$SHOW_HISTORY" == "true" ]]; then
    show_performance_history "$HISTORY_DAYS"
elif [[ "$SHOW_RECOMMENDATIONS" == "true" ]]; then
    generate_recommendations
elif [[ "$REAL_TIME" == "true" ]]; then
    real_time_monitor "$INTERVAL" "$DURATION"
elif [[ "$JSON_OUTPUT" == "true" ]]; then
    # JSON output for automation
    cpu_usage=$(get_cpu_usage)
    memory_usage=$(get_memory_usage)
    disk_usage=$(get_disk_usage)
    load_avg=$(get_system_load)
    
    cat << EOF
{
  "timestamp": "$(date -Iseconds)",
  "metrics": {
    "cpu_usage": $cpu_usage,
    "memory_usage": $memory_usage,
    "disk_usage": $disk_usage,
    "load_average": $load_avg,
    "nix_store_size_gb": $(get_nix_store_size),
    "process_count": $(get_process_count),
    "uptime": "$(get_uptime)"
  },
  "thresholds": {
    "cpu_warning": $CPU_WARNING_THRESHOLD,
    "cpu_critical": $CPU_CRITICAL_THRESHOLD,
    "memory_warning": $MEMORY_WARNING_THRESHOLD,
    "memory_critical": $MEMORY_CRITICAL_THRESHOLD
  }
}
EOF
else
    main_monitor
    if [[ $? -eq 0 ]]; then
        echo ""
        echo -e "${GREEN}${CHECK} Performance monitoring completed${NC}"
        echo "Use --help for more monitoring options"
    fi
fi