# Performance Monitoring System
# Comprehensive monitoring with data collection, analysis, and alerting
{ config, lib, pkgs, platformInfo, ... }:

with lib;

{
  imports = [
    ./collectors/system-metrics.nix
    ./collectors/build-times.nix
    ./collectors/tool-performance.nix
  ];

  config = mkIf config.dotfiles.performance.enable {
    # Main metrics collection script
    environment.systemPackages = with pkgs; [
      # Primary metrics collection tool
      (writeShellScriptBin "dotfiles-collect-metrics" ''
        #!/bin/bash
        
        # Centralized metrics collection for dotfiles performance monitoring
        
        set -euo pipefail
        
        METRICS_DB="''${1:-/var/lib/dotfiles-performance/metrics/performance.db}"
        USER_METRICS_DIR="/Users/yuki/.local/share/dotfiles-performance/metrics"
        
        mkdir -p "$(dirname "$METRICS_DB")"
        mkdir -p "$USER_METRICS_DIR"
        
        TIMESTAMP=$(date +%s)
        
        echo "Collecting metrics at $(date)"
        
        # Initialize variables
        CPU_USAGE=0
        MEMORY_USAGE=0
        DISK_USAGE=0
        LOAD_1M=0
        LOAD_5M=0
        LOAD_15M=0
        
        ${optionalString config.dotfiles.performance.monitoring.systemMetrics.collectCPU ''
          # CPU usage collection
          if [ "$(uname -s)" = "Darwin" ]; then
            # macOS: Use iostat for CPU
            CPU_USAGE=$(iostat -c 1 | tail -1 | awk '{print 100-$6}')
          else
            # Linux: Use /proc/stat
            CPU_USAGE=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$3+$4+$5)} END {print usage}')
          fi
        ''}
        
        ${optionalString config.dotfiles.performance.monitoring.systemMetrics.collectMemory ''
          # Memory usage collection
          if [ "$(uname -s)" = "Darwin" ]; then
            # macOS: Use vm_stat
            MEMORY_PRESSURE=$(memory_pressure 2>/dev/null | grep "System-wide memory free percentage" | awk '{print $6}' | tr -d '%' || echo "20")
            MEMORY_USAGE=$((100 - MEMORY_PRESSURE))
          else
            # Linux: Use free command
            MEMORY_USAGE=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
          fi
        ''}
        
        ${optionalString config.dotfiles.performance.monitoring.systemMetrics.collectDisk ''
          # Disk usage collection
          DISK_USAGE=$(df /nix/store | tail -1 | awk '{print $(NF-1)}' | sed 's/%//')
        ''}
        
        ${optionalString config.dotfiles.performance.monitoring.systemMetrics.collectNetwork ''
          # Load average collection
          if [ "$(uname -s)" = "Darwin" ]; then
            LOAD_AVG=$(uptime | awk '{print $(NF-2) " " $(NF-1) " " $NF}' | tr -d ',')
          else
            LOAD_AVG=$(cat /proc/loadavg)
          fi
          LOAD_1M=$(echo "$LOAD_AVG" | awk '{print $1}')
          LOAD_5M=$(echo "$LOAD_AVG" | awk '{print $2}')  
          LOAD_15M=$(echo "$LOAD_AVG" | awk '{print $3}')
        ''}
        
        # Insert into database if enabled
        if [ -f "$METRICS_DB" ]; then
          ${optionalString config.dotfiles.performance.monitoring.systemMetrics.enable ''
            # Insert into database
            ${pkgs.sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
              INSERT INTO system_metrics (
                timestamp, cpu_usage_percent, memory_usage_percent, 
                disk_usage_percent, load_average_1m, load_average_5m, load_average_15m
              ) VALUES (
                $TIMESTAMP, $CPU_USAGE, $MEMORY_USAGE, 
                $DISK_USAGE, $LOAD_1M, $LOAD_5M, $LOAD_15M
              );
EOF
          ''}
          
          # Check for alerts
          ${optionalString config.dotfiles.performance.monitoring.systemMetrics.enable ''
            if (( $(echo "$CPU_USAGE > ${toString config.dotfiles.performance.monitoring.alertThresholds.cpuUsage}" | bc -l) )); then
              echo "ALERT: High CPU usage: $CPU_USAGE%" >> "$USER_METRICS_DIR/alerts.log"
              # Send notification if available
              command -v osascript >/dev/null && osascript -e "display notification \"High CPU usage: $CPU_USAGE%\" with title \"Performance Alert\""
            fi
            
            if (( $(echo "$MEMORY_USAGE > ${toString config.dotfiles.performance.monitoring.alertThresholds.memoryUsage}" | bc -l) )); then
              echo "ALERT: High memory usage: $MEMORY_USAGE%" >> "$USER_METRICS_DIR/alerts.log"
              command -v osascript >/dev/null && osascript -e "display notification \"High memory usage: $MEMORY_USAGE%\" with title \"Performance Alert\""
            fi
          ''}
        fi
        
        # Log to user metrics
        echo "$(date): CPU:$CPU_USAGE% MEM:$MEMORY_USAGE% DISK:$DISK_USAGE% LOAD:$LOAD_1M" >> "$USER_METRICS_DIR/metrics.log"
        
        echo "Metrics collection completed"
      '')
      
      # Metrics viewing tool
      (writeShellScriptBin "dotfiles-view-metrics" ''
        #!/bin/bash
        
        METRICS_DB="''${1:-/var/lib/dotfiles-performance/metrics/performance.db}"
        HOURS="''${2:-24}"
        
        if [ ! -f "$METRICS_DB" ]; then
          echo "Metrics database not found at $METRICS_DB"
          exit 1
        fi
        
        CUTOFF_TIME=$(($(date +%s) - (HOURS * 3600)))
        
        echo "=== System Metrics (Last $HOURS hours) ==="
        ${sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
          .mode column
          .headers on
          .width 20 8 8 8 8
          
          SELECT 
            datetime(timestamp, 'unixepoch', 'localtime') as "Time",
            printf("%.1f", cpu_usage_percent) as "CPU%",
            printf("%.1f", memory_usage_percent) as "Memory%",
            printf("%.1f", disk_usage_percent) as "Disk%",
            printf("%.2f", load_average_1m) as "Load"
          FROM system_metrics 
          WHERE timestamp > $CUTOFF_TIME
          ORDER BY timestamp DESC
          LIMIT 20;
EOF
        
        echo ""
        echo "=== Summary Statistics ==="
        ${sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
          SELECT 
            printf("Average CPU: %.1f%%", AVG(cpu_usage_percent)),
            printf("Average Memory: %.1f%%", AVG(memory_usage_percent)),
            printf("Average Load: %.2f", AVG(load_average_1m))
          FROM system_metrics 
          WHERE timestamp > $CUTOFF_TIME;
EOF
      '')
    ];
    
    # macOS launchd service for continuous monitoring
    launchd.user.agents.dotfiles-performance-monitor = mkIf (platformInfo.isDarwin or false) {
      serviceConfig = {
        Label = "org.dotfiles.performance-monitor";
        ProgramArguments = [
          "${pkgs.writeShellScript "performance-monitor" ''
            #!/bin/bash
            set -euo pipefail
            
            while true; do
              dotfiles-collect-metrics
              sleep ${toString config.dotfiles.performance.monitoring.interval}
            done
          ''}"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardErrorPath = "/Users/yuki/.local/share/dotfiles-performance/logs/monitor-error.log";
        StandardOutPath = "/Users/yuki/.local/share/dotfiles-performance/logs/monitor-output.log";
      };
    };
    
    # Note: Linux systemd services would be configured in a separate Linux-specific module
  };
}