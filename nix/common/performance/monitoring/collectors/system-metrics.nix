# System Metrics Collector
# Collects CPU, memory, disk, and network performance data
{ config, lib, pkgs, platformInfo, ... }:

with lib;

{
  options.dotfiles.performance.monitoring.systemMetrics = {
    enable = mkEnableOption "System metrics collection";
    
    collectCPU = mkOption {
      type = types.bool;
      default = true;
      description = "Collect CPU usage metrics";
    };
    
    collectMemory = mkOption {
      type = types.bool;
      default = true;
      description = "Collect memory usage metrics";
    };
    
    collectDisk = mkOption {
      type = types.bool;
      default = true;
      description = "Collect disk I/O metrics";
    };
    
    collectNetwork = mkOption {
      type = types.bool;
      default = true;
      description = "Collect network usage metrics";
    };
    
    detailedMetrics = mkOption {
      type = types.bool;
      default = false;
      description = "Collect detailed per-process metrics";
    };
  };

  config = mkIf (config.dotfiles.performance.enable && config.dotfiles.performance.monitoring.systemMetrics.enable) {
    # System metrics collection script
    environment.systemPackages = with pkgs; [
      (writeShellScriptBin "dotfiles-collect-metrics" ''
        #!/bin/bash
        
        # System Metrics Collection Script
        # Supports both macOS and Linux with platform-specific optimizations
        
        set -euo pipefail
        
        METRICS_DB="''${1:-/var/lib/dotfiles-performance/metrics/performance.db}"
        USER_METRICS_DIR="/Users/yuki/.local/share/dotfiles-performance/metrics"
        
        # Ensure database exists
        if [ ! -f "$METRICS_DB" ]; then
          echo "Error: Metrics database not found at $METRICS_DB"
          exit 1
        fi
        
        # Get current timestamp
        TIMESTAMP=$(date +%s)
        
        # Platform detection
        PLATFORM="$(uname -s)"
        
        # Initialize metrics variables
        CPU_USAGE=0
        MEMORY_USAGE=0
        DISK_USAGE=0
        LOAD_1M=0
        LOAD_5M=0
        LOAD_15M=0
        DISK_READ_MB=0
        DISK_WRITE_MB=0
        NET_RX_MB=0
        NET_TX_MB=0
        
        # Collect CPU metrics
        ${optionalString config.dotfiles.performance.monitoring.systemMetrics.collectCPU ''
          if [ "$PLATFORM" = "Darwin" ]; then
            # macOS CPU collection
            CPU_USAGE=$(top -l 1 -n 0 | grep "CPU usage" | awk '{print $3}' | sed 's/%//')
            
            # Load average
            LOAD_AVG=$(uptime | sed 's/.*load averages: //')
            LOAD_1M=$(echo "$LOAD_AVG" | awk '{print $1}')
            LOAD_5M=$(echo "$LOAD_AVG" | awk '{print $2}')
            LOAD_15M=$(echo "$LOAD_AVG" | awk '{print $3}')
          else
            # Linux CPU collection
            CPU_USAGE=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$3+$4+$5)} END {printf "%.1f", usage}')
            
            # Load average from /proc/loadavg
            read LOAD_1M LOAD_5M LOAD_15M _ _ < /proc/loadavg
          fi
          
          echo "CPU Usage: $CPU_USAGE%, Load: $LOAD_1M $LOAD_5M $LOAD_15M"
        ''}
        
        # Collect Memory metrics  
        ${optionalString config.dotfiles.performance.monitoring.systemMetrics.collectMemory ''
          if [ "$PLATFORM" = "Darwin" ]; then
            # macOS memory collection using vm_stat
            VM_STAT=$(vm_stat)
            PAGE_SIZE=$(vm_stat | grep "page size" | awk '{print $8}')
            
            FREE_PAGES=$(echo "$VM_STAT" | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
            ACTIVE_PAGES=$(echo "$VM_STAT" | grep "Pages active" | awk '{print $3}' | sed 's/\.//')
            INACTIVE_PAGES=$(echo "$VM_STAT" | grep "Pages inactive" | awk '{print $3}' | sed 's/\.//')
            SPECULATIVE_PAGES=$(echo "$VM_STAT" | grep "Pages speculative" | awk '{print $3}' | sed 's/\.//')
            WIRED_PAGES=$(echo "$VM_STAT" | grep "Pages wired down" | awk '{print $4}' | sed 's/\.//')
            
            TOTAL_PAGES=$((FREE_PAGES + ACTIVE_PAGES + INACTIVE_PAGES + SPECULATIVE_PAGES + WIRED_PAGES))
            USED_PAGES=$((TOTAL_PAGES - FREE_PAGES))
            
            MEMORY_USAGE=$(echo "scale=1; ($USED_PAGES * 100) / $TOTAL_PAGES" | bc)
          else
            # Linux memory collection
            MEMORY_USAGE=$(free | awk 'NR==2{printf "%.1f", $3*100/$2}')
          fi
          
          echo "Memory Usage: $MEMORY_USAGE%"
        ''}
        
        # Collect Disk metrics
        ${optionalString config.dotfiles.performance.monitoring.systemMetrics.collectDisk ''
          # Disk usage percentage (cross-platform)
          DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
          
          if [ "$PLATFORM" = "Darwin" ]; then
            # macOS disk I/O (approximation using iostat if available)
            if command -v iostat >/dev/null 2>&1; then
              DISK_IO=$(iostat -d 1 2 | tail -1)
              DISK_READ_MB=$(echo "$DISK_IO" | awk '{print $3}')
              DISK_WRITE_MB=$(echo "$DISK_IO" | awk '{print $4}')
            fi
          else
            # Linux disk I/O using /proc/diskstats
            if [ -f /proc/diskstats ]; then
              # This is a simplified version - could be enhanced
              DISK_READ_MB=0
              DISK_WRITE_MB=0
            fi
          fi
          
          echo "Disk Usage: $DISK_USAGE%, I/O: R=$DISK_READ_MB MB/s W=$DISK_WRITE_MB MB/s"
        ''}
        
        # Collect Network metrics
        ${optionalString config.dotfiles.performance.monitoring.systemMetrics.collectNetwork ''
          if [ "$PLATFORM" = "Darwin" ]; then
            # macOS network statistics
            if command -v netstat >/dev/null 2>&1; then
              # Simplified network monitoring
              NET_RX_MB=0
              NET_TX_MB=0
            fi
          else
            # Linux network statistics from /proc/net/dev
            if [ -f /proc/net/dev ]; then
              # This is a placeholder - would need baseline measurement
              NET_RX_MB=0  
              NET_TX_MB=0
            fi
          fi
          
          echo "Network: RX=$NET_RX_MB MB/s TX=$NET_TX_MB MB/s"
        ''}
        
        # Store metrics in database
        ${pkgs.sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
          INSERT INTO system_metrics (
            timestamp, cpu_usage_percent, memory_usage_percent, disk_usage_percent,
            load_average_1m, load_average_5m, load_average_15m,
            disk_read_mb_per_sec, disk_write_mb_per_sec,
            network_rx_mb_per_sec, network_tx_mb_per_sec
          ) VALUES (
            $TIMESTAMP, $CPU_USAGE, $MEMORY_USAGE, $DISK_USAGE,
            $LOAD_1M, $LOAD_5M, $LOAD_15M,
            $DISK_READ_MB, $DISK_WRITE_MB,
            $NET_RX_MB, $NET_TX_MB
          );
EOF
        
        # Log collection success
        echo "$(date): Metrics collected successfully" >> "$USER_METRICS_DIR/collection.log"
        
        # Optional: Clean old metrics based on retention policy
        RETENTION_DAYS=${toString config.dotfiles.performance.monitoring.retention}
        CUTOFF_TIMESTAMP=$((TIMESTAMP - (RETENTION_DAYS * 24 * 3600)))
        
        ${pkgs.sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
          DELETE FROM system_metrics WHERE timestamp < $CUTOFF_TIMESTAMP;
EOF
        
        echo "Metrics collection completed at $(date)"
      '')
      
      # Quick metrics viewer script
      (writeShellScriptBin "dotfiles-view-metrics" ''
        #!/bin/bash
        
        METRICS_DB="''${1:-/var/lib/dotfiles-performance/metrics/performance.db}"
        HOURS="''${2:-24}"
        
        if [ ! -f "$METRICS_DB" ]; then
          echo "Metrics database not found at $METRICS_DB"
          exit 1
        fi
        
        CUTOFF_TIME=$(($(date +%s) - (HOURS * 3600)))
        
        echo "=== Performance Metrics (Last $HOURS hours) ==="
        echo
        
        # System metrics summary
        ${pkgs.sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
          .mode column
          .headers on
          .width 12 8 8 8 8 8 8
          
          SELECT 
            datetime(timestamp, 'unixepoch', 'localtime') as Time,
            printf("%.1f", cpu_usage_percent) as "CPU%",
            printf("%.1f", memory_usage_percent) as "Memory%", 
            printf("%.1f", disk_usage_percent) as "Disk%",
            printf("%.2f", load_average_1m) as "Load1m",
            printf("%.2f", load_average_5m) as "Load5m",
            printf("%.2f", load_average_15m) as "Load15m"
          FROM system_metrics 
          WHERE timestamp > $CUTOFF_TIME 
          ORDER BY timestamp DESC 
          LIMIT 20;
EOF
        
        echo
        echo "=== Average Performance ==="
        ${pkgs.sqlite}/bin/sqlite3 "$METRICS_DB" << EOF
          SELECT 
            printf("Average CPU: %.1f%%", AVG(cpu_usage_percent)),
            printf("Average Memory: %.1f%%", AVG(memory_usage_percent)),
            printf("Average Load: %.2f", AVG(load_average_1m))
          FROM system_metrics 
          WHERE timestamp > $CUTOFF_TIME;
EOF
      '')
    ] ++ (
      # Additional detailed process monitoring for comprehensive profile
      lib.optionals config.dotfiles.performance.monitoring.systemMetrics.detailedMetrics (with pkgs; [
      (writeShellScriptBin "dotfiles-detailed-metrics" ''
        #!/bin/bash
        
        # Detailed process-level metrics collection
        METRICS_DB="''${1:-/var/lib/dotfiles-performance/metrics/performance.db}"
        
        # Top CPU consuming processes
        echo "=== Top CPU Processes ==="
        if [ "$(uname -s)" = "Darwin" ]; then
          ps -eo pid,pcpu,pmem,comm --sort=-pcpu | head -10
        else
          ps -eo pid,pcpu,pmem,comm --sort=-pcpu | head -10
        fi
        
        # Top Memory consuming processes  
        echo "=== Top Memory Processes ==="
        if [ "$(uname -s)" = "Darwin" ]; then
          ps -eo pid,pcpu,pmem,comm --sort=-pmem | head -10
        else
          ps -eo pid,pcpu,pmem,comm --sort=-pmem | head -10
        fi
        
        # Development tool processes
        echo "=== Development Tool Processes ==="
        ps aux | grep -E "(code|nvim|git|nix|home-manager)" | grep -v grep
      '')
    ]));
  };
}