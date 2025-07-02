# Performance Monitoring Subsystem
# Coordinates all monitoring collectors and data processing
{ config, lib, pkgs, platformInfo, ... }:

with lib;

{
  imports = [
    ./collectors/system-metrics.nix
    ./collectors/build-times.nix  
    ./collectors/tool-performance.nix
    ./storage/metrics-db.nix
  ];

  options.dotfiles.performance.monitoring = {
    systemMetrics = {
      enable = mkEnableOption "System metrics collection (CPU, memory, disk, network)";
    };
    
    buildTimes = {
      enable = mkEnableOption "Build time tracking for Nix operations";
    };
    
    toolPerformance = {
      enable = mkEnableOption "Development tool performance monitoring";
    };
  };

  config = mkIf config.dotfiles.performance.enable {
    # Create monitoring service for data collection
    launchd.user.agents.dotfiles-performance-monitor = mkIf (platformInfo.isDarwin or false) {
      serviceConfig = {
        Label = "org.dotfiles.performance-monitor";
        ProgramArguments = [
          "${pkgs.writeShellScript "performance-monitor" ''
            #!/bin/bash
            
            # Performance monitoring main loop
            METRICS_DB="/var/lib/dotfiles-performance/metrics/performance.db"
            USER_METRICS_DIR="/Users/yuki/.local/share/dotfiles-performance/metrics"
            INTERVAL=${toString config.dotfiles.performance.monitoring.interval}
            
            # Ensure directories exist
            mkdir -p "$(dirname "$METRICS_DB")"
            mkdir -p "$USER_METRICS_DIR"
            
            # Main monitoring loop
            while true; do
              TIMESTAMP=$(date +%s)
              
              # Collect system metrics if enabled
              ${optionalString config.dotfiles.performance.monitoring.systemMetrics.enable ''
                # CPU usage
                CPU_USAGE=$(ps -A -o %cpu | awk '{sum+=$1} END {print sum}')
                
                # Memory usage  
                MEMORY_INFO=$(vm_stat | grep -E "(Pages free|Pages active|Pages inactive|Pages speculative|Pages wired down)")
                MEMORY_USAGE=$(echo "$MEMORY_INFO" | awk '
                  /Pages free/ {free=$3}
                  /Pages active/ {active=$3}  
                  /Pages inactive/ {inactive=$3}
                  /Pages speculative/ {spec=$3}
                  /Pages wired/ {wired=$4}
                  END {
                    total=free+active+inactive+spec+wired
                    used=total-free
                    print (used/total)*100
                  }
                ')
                
                # Load average
                LOAD_AVG=$(uptime | sed 's/.*load averages: //' | tr ' ' '\n')
                LOAD_1M=$(echo "$LOAD_AVG" | sed -n '1p')
                LOAD_5M=$(echo "$LOAD_AVG" | sed -n '2p')  
                LOAD_15M=$(echo "$LOAD_AVG" | sed -n '3p')
                
                # Disk usage
                DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
                
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
              
              # Log monitoring activity
              echo "$(date): Collected metrics - CPU: $CPU_USAGE%, Memory: $MEMORY_USAGE%, Load: $LOAD_1M" >> "$USER_METRICS_DIR/monitoring.log"
              
              # Sleep until next collection
              sleep $INTERVAL
            done
          ''}"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardErrorPath = "/Users/yuki/.local/share/dotfiles-performance/logs/monitor-error.log";
        StandardOutPath = "/Users/yuki/.local/share/dotfiles-performance/logs/monitor-output.log";
      };
    };
    
    # Linux systemd service (for non-Darwin platforms)
    systemd.user.services.dotfiles-performance-monitor = mkIf (!(platformInfo.isDarwin or false)) {
      description = "Dotfiles Performance Monitoring Service";
      wantedBy = [ "default.target" ];
      after = [ "graphical-session.target" ];
      
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = 10;
        Environment = [
          "PATH=${makeBinPath (with pkgs; [ sqlite jq procps sysstat bc ])}"
        ];
      };
      
      script = ''
        # Similar monitoring script for Linux
        METRICS_DB="$HOME/.local/share/dotfiles-performance/metrics/performance.db"
        INTERVAL=${toString config.dotfiles.performance.monitoring.interval}
        
        mkdir -p "$(dirname "$METRICS_DB")"
        
        while true; do
          TIMESTAMP=$(date +%s)
          
          ${optionalString config.dotfiles.performance.monitoring.systemMetrics.enable ''
            # Linux-specific system metrics collection
            CPU_USAGE=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$3+$4+$5)} END {print usage}')
            MEMORY_USAGE=$(free | awk 'NR==2{printf "%.2f", $3*100/$2}')
            DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
            
            LOAD_AVG=$(cat /proc/loadavg)
            LOAD_1M=$(echo "$LOAD_AVG" | awk '{print $1}')
            LOAD_5M=$(echo "$LOAD_AVG" | awk '{print $2}')
            LOAD_15M=$(echo "$LOAD_AVG" | awk '{print $3}')
            
            sqlite3 "$METRICS_DB" << EOF
              INSERT INTO system_metrics (
                timestamp, cpu_usage_percent, memory_usage_percent,
                disk_usage_percent, load_average_1m, load_average_5m, load_average_15m
              ) VALUES (
                $TIMESTAMP, $CPU_USAGE, $MEMORY_USAGE,
                $DISK_USAGE, $LOAD_1M, $LOAD_5M, $LOAD_15M
              );
EOF
          ''}
          
          sleep $INTERVAL
        done
      '';
    };
  };
}