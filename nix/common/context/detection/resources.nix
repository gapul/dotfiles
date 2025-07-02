{ config, lib, pkgs, ... }:

with lib;

{
  options = {
    dotfiles.context.resourceMonitoring = {
      enable = mkEnableOption "Intelligent resource monitoring and analysis system";
      
      batteryMonitoring = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable battery status monitoring and analysis";
        };
        
        thresholds = mkOption {
          type = types.attrsOf types.int;
          default = {
            critical = 10;
            low = 25;
            moderate = 50;
            good = 75;
          };
          description = "Battery level thresholds for status classification";
        };
        
        powerModeAdjustment = mkOption {
          type = types.bool;
          default = true;
          description = "Enable automatic power mode suggestions based on battery";
        };
      };
      
      cpuMonitoring = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable CPU usage monitoring and analysis";
        };
        
        thresholds = mkOption {
          type = types.attrsOf types.int;
          default = {
            idle = 10;
            light = 30;
            moderate = 60;
            heavy = 85;
          };
          description = "CPU usage thresholds for load classification";
        };
        
        thermalMonitoring = mkOption {
          type = types.bool;
          default = true;
          description = "Enable thermal monitoring for CPU temperature";
        };
      };
      
      memoryMonitoring = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable memory usage monitoring and analysis";
        };
        
        thresholds = mkOption {
          type = types.attrsOf types.int;
          default = {
            available = 80;
            moderate = 60;
            high = 40;
            critical = 20;
          };
          description = "Memory availability thresholds (percentage free)";
        };
        
        swapMonitoring = mkOption {
          type = types.bool;
          default = true;
          description = "Enable swap usage monitoring";
        };
      };
      
      networkMonitoring = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable network performance monitoring";
        };
        
        bandwidthTracking = mkOption {
          type = types.bool;
          default = true;
          description = "Track network bandwidth usage";
        };
        
        connectivityTests = mkOption {
          type = types.bool;
          default = true;
          description = "Perform network connectivity and latency tests";
        };
        
        qualityThresholds = mkOption {
          type = types.attrsOf types.int;
          default = {
            excellent = 10;    # <10ms latency
            good = 50;         # <50ms latency
            moderate = 150;    # <150ms latency
            poor = 500;        # <500ms latency
          };
          description = "Network quality thresholds based on latency (ms)";
        };
      };
      
      storageMonitoring = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable storage space and performance monitoring";
        };
        
        spaceThresholds = mkOption {
          type = types.attrsOf types.int;
          default = {
            available = 80;
            moderate = 60;
            low = 40;
            critical = 10;
          };
          description = "Storage space thresholds (percentage free)";
        };
        
        ioMonitoring = mkOption {
          type = types.bool;
          default = true;
          description = "Monitor disk I/O performance";
        };
      };
      
      alerting = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable resource alerts and notifications";
        };
        
        alertThresholds = mkOption {
          type = types.attrsOf types.str;
          default = {
            battery = "critical";
            cpu = "heavy";
            memory = "critical";
            storage = "critical";
            network = "poor";
          };
          description = "Alert trigger thresholds for each resource type";
        };
      };
    };
  };

  config = mkIf config.dotfiles.context.resourceMonitoring.enable {
    environment.systemPackages = with pkgs; [
      # Resource monitoring command
      (writeShellScriptBin "context-monitor-resources" ''
        #!/bin/bash
        
        # Intelligent resource monitoring and analysis
        
        set -euo pipefail
        
        ACTION="''${1:-status}"
        DURATION="''${2:-10}"  # seconds for monitoring
        OUTPUT_FORMAT="''${3:-summary}"  # summary, json, detailed, alert
        
        echo "🔋 Resource Monitoring System"
        echo "============================"
        echo "Action: $ACTION"
        echo "⏰ Monitoring time: $(date)"
        echo ""
        
        # Initialize resource data
        BATTERY_LEVEL="unknown"
        BATTERY_STATUS="unknown"
        POWER_SOURCE="unknown"
        CPU_USAGE="unknown"
        CPU_TEMP="unknown"
        MEMORY_USAGE="unknown"
        MEMORY_AVAILABLE="unknown"
        SWAP_USAGE="unknown"
        NETWORK_LATENCY="unknown"
        NETWORK_QUALITY="unknown"
        STORAGE_USAGE="unknown"
        STORAGE_AVAILABLE="unknown"
        
        case "$ACTION" in
          "status"|"monitor"|"alert")
            
            # Battery monitoring
            ${optionalString config.dotfiles.context.resourceMonitoring.batteryMonitoring.enable ''
              echo "🔋 Battery Analysis:"
              
              if [[ "$(uname)" == "Darwin" ]]; then
                # macOS battery monitoring
                if command -v pmset >/dev/null 2>&1; then
                  BATTERY_INFO=$(pmset -g batt)
                  BATTERY_LEVEL=$(echo "$BATTERY_INFO" | grep -Eo "[0-9]+%" | head -1 | tr -d '%')
                  POWER_SOURCE=$(echo "$BATTERY_INFO" | grep -o "AC Power\\|Battery Power" | head -1)
                  
                  # Get charging status
                  if echo "$BATTERY_INFO" | grep -q "charging"; then
                    BATTERY_STATUS="charging"
                    STATUS_EMOJI="⚡"
                  elif echo "$BATTERY_INFO" | grep -q "charged"; then
                    BATTERY_STATUS="charged"
                    STATUS_EMOJI="✅"
                  else
                    BATTERY_STATUS="discharging"
                    STATUS_EMOJI="🔋"
                  fi
                  
                  # Determine battery health
                  if [[ "$BATTERY_LEVEL" -gt ${toString config.dotfiles.context.resourceMonitoring.batteryMonitoring.thresholds.good} ]]; then
                    BATTERY_HEALTH="excellent"
                    HEALTH_EMOJI="💚"
                  elif [[ "$BATTERY_LEVEL" -gt ${toString config.dotfiles.context.resourceMonitoring.batteryMonitoring.thresholds.moderate} ]]; then
                    BATTERY_HEALTH="good"
                    HEALTH_EMOJI="💛"
                  elif [[ "$BATTERY_LEVEL" -gt ${toString config.dotfiles.context.resourceMonitoring.batteryMonitoring.thresholds.low} ]]; then
                    BATTERY_HEALTH="moderate"
                    HEALTH_EMOJI="🧡"
                  elif [[ "$BATTERY_LEVEL" -gt ${toString config.dotfiles.context.resourceMonitoring.batteryMonitoring.thresholds.critical} ]]; then
                    BATTERY_HEALTH="low"
                    HEALTH_EMOJI="❤️"
                  else
                    BATTERY_HEALTH="critical"
                    HEALTH_EMOJI="🚨"
                  fi
                  
                  echo "  $STATUS_EMOJI Status: $BATTERY_STATUS ($BATTERY_LEVEL%)"
                  echo "  $HEALTH_EMOJI Health: $BATTERY_HEALTH"
                  echo "  🔌 Power source: $POWER_SOURCE"
                  
                  # Time remaining estimate
                  TIME_REMAINING=$(echo "$BATTERY_INFO" | grep -o "[0-9]:[0-9][0-9]" | head -1 || echo "")
                  [[ -n "$TIME_REMAINING" ]] && echo "  ⏰ Time remaining: $TIME_REMAINING"
                  
                else
                  echo "  ⚠️  Battery information unavailable"
                fi
              elif [[ "$(uname)" == "Linux" ]]; then
                # Linux battery monitoring
                if [[ -d "/sys/class/power_supply" ]]; then
                  for battery in /sys/class/power_supply/BAT*; do
                    if [[ -f "$battery/capacity" ]]; then
                      BATTERY_LEVEL=$(cat "$battery/capacity")
                      STATUS_FILE="$battery/status"
                      [[ -f "$STATUS_FILE" ]] && BATTERY_STATUS=$(cat "$STATUS_FILE" | tr '[:upper:]' '[:lower:]')
                      
                      echo "  🔋 Battery: $BATTERY_LEVEL% ($BATTERY_STATUS)"
                      break
                    fi
                  done
                else
                  echo "  ⚠️  Battery information unavailable"
                fi
              fi
              echo ""
            ''}
            
            # CPU monitoring
            ${optionalString config.dotfiles.context.resourceMonitoring.cpuMonitoring.enable ''
              echo "🖥️  CPU Analysis:"
              
              if [[ "$(uname)" == "Darwin" ]]; then
                # macOS CPU monitoring
                CPU_USAGE=$(top -l 1 | grep "CPU usage" | awk '{print $3}' | tr -d '%' || echo "0")
                
                # Get CPU temperature (if available)
                if command -v osx-cpu-temp >/dev/null 2>&1; then
                  CPU_TEMP=$(osx-cpu-temp 2>/dev/null | tr -d '°C' || echo "unknown")
                elif command -v sudo >/dev/null 2>&1; then
                  # Try powermetrics (requires sudo)
                  CPU_TEMP=$(sudo powermetrics -n 1 -i 1000 --samplers smc -a --hide-cpu-duty-cycle 2>/dev/null | grep "CPU die temperature" | awk '{print $4}' | tr -d '°C' || echo "unknown")
                fi
                
              elif [[ "$(uname)" == "Linux" ]]; then
                # Linux CPU monitoring
                CPU_USAGE=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$3+$4)} END {print int(usage)}')
                
                # Get CPU temperature
                if [[ -f "/sys/class/thermal/thermal_zone0/temp" ]]; then
                  CPU_TEMP_RAW=$(cat /sys/class/thermal/thermal_zone0/temp)
                  CPU_TEMP=$((CPU_TEMP_RAW / 1000))
                fi
              fi
              
              # Determine CPU load level
              if [[ "$CPU_USAGE" =~ ^[0-9]+$ ]]; then
                if [[ "$CPU_USAGE" -lt ${toString config.dotfiles.context.resourceMonitoring.cpuMonitoring.thresholds.idle} ]]; then
                  CPU_LOAD="idle"
                  LOAD_EMOJI="😴"
                elif [[ "$CPU_USAGE" -lt ${toString config.dotfiles.context.resourceMonitoring.cpuMonitoring.thresholds.light} ]]; then
                  CPU_LOAD="light"
                  LOAD_EMOJI="💚"
                elif [[ "$CPU_USAGE" -lt ${toString config.dotfiles.context.resourceMonitoring.cpuMonitoring.thresholds.moderate} ]]; then
                  CPU_LOAD="moderate"
                  LOAD_EMOJI="💛"
                elif [[ "$CPU_USAGE" -lt ${toString config.dotfiles.context.resourceMonitoring.cpuMonitoring.thresholds.heavy} ]]; then
                  CPU_LOAD="heavy"
                  LOAD_EMOJI="🧡"
                else
                  CPU_LOAD="critical"
                  LOAD_EMOJI="🚨"
                fi
                
                echo "  $LOAD_EMOJI Usage: $CPU_USAGE% ($CPU_LOAD)"
              else
                echo "  ⚠️  CPU usage unavailable"
              fi
              
              [[ "$CPU_TEMP" != "unknown" ]] && echo "  🌡️  Temperature: $CPU_TEMP°C"
              
              # Core count
              if [[ "$(uname)" == "Darwin" ]]; then
                CORES=$(sysctl -n hw.ncpu)
              else
                CORES=$(nproc)
              fi
              echo "  🔢 Cores: $CORES"
              echo ""
            ''}
            
            # Memory monitoring
            ${optionalString config.dotfiles.context.resourceMonitoring.memoryMonitoring.enable ''
              echo "💾 Memory Analysis:"
              
              if [[ "$(uname)" == "Darwin" ]]; then
                # macOS memory monitoring
                VM_STAT=$(vm_stat)
                PAGE_SIZE=$(vm_stat | grep "page size" | awk '{print $8}')
                
                FREE_PAGES=$(echo "$VM_STAT" | grep "free:" | awk '{print $3}' | tr -d '.')
                INACTIVE_PAGES=$(echo "$VM_STAT" | grep "inactive:" | awk '{print $3}' | tr -d '.')
                ACTIVE_PAGES=$(echo "$VM_STAT" | grep "active:" | awk '{print $3}' | tr -d '.')
                WIRED_PAGES=$(echo "$VM_STAT" | grep "wired down:" | awk '{print $4}' | tr -d '.')
                
                FREE_MB=$(( (FREE_PAGES + INACTIVE_PAGES) * PAGE_SIZE / 1024 / 1024 ))
                USED_MB=$(( (ACTIVE_PAGES + WIRED_PAGES) * PAGE_SIZE / 1024 / 1024 ))
                TOTAL_MB=$(( FREE_MB + USED_MB ))
                
                MEMORY_USAGE=$(( USED_MB * 100 / TOTAL_MB ))
                MEMORY_AVAILABLE=$(( FREE_MB * 100 / TOTAL_MB ))
                
              elif [[ "$(uname)" == "Linux" ]]; then
                # Linux memory monitoring
                MEM_INFO=$(cat /proc/meminfo)
                TOTAL_KB=$(echo "$MEM_INFO" | grep "MemTotal:" | awk '{print $2}')
                AVAILABLE_KB=$(echo "$MEM_INFO" | grep "MemAvailable:" | awk '{print $2}')
                
                TOTAL_MB=$(( TOTAL_KB / 1024 ))
                AVAILABLE_MB=$(( AVAILABLE_KB / 1024 ))
                USED_MB=$(( TOTAL_MB - AVAILABLE_MB ))
                
                MEMORY_USAGE=$(( USED_MB * 100 / TOTAL_MB ))
                MEMORY_AVAILABLE=$(( AVAILABLE_MB * 100 / TOTAL_MB ))
              fi
              
              # Determine memory status
              if [[ "$MEMORY_AVAILABLE" -gt ${toString config.dotfiles.context.resourceMonitoring.memoryMonitoring.thresholds.available} ]]; then
                MEMORY_STATUS="excellent"
                MEM_EMOJI="💚"
              elif [[ "$MEMORY_AVAILABLE" -gt ${toString config.dotfiles.context.resourceMonitoring.memoryMonitoring.thresholds.moderate} ]]; then
                MEMORY_STATUS="good"
                MEM_EMOJI="💛"
              elif [[ "$MEMORY_AVAILABLE" -gt ${toString config.dotfiles.context.resourceMonitoring.memoryMonitoring.thresholds.high} ]]; then
                MEMORY_STATUS="moderate"
                MEM_EMOJI="🧡"
              elif [[ "$MEMORY_AVAILABLE" -gt ${toString config.dotfiles.context.resourceMonitoring.memoryMonitoring.thresholds.critical} ]]; then
                MEMORY_STATUS="high"
                MEM_EMOJI="❤️"
              else
                MEMORY_STATUS="critical"
                MEM_EMOJI="🚨"
              fi
              
              echo "  $MEM_EMOJI Status: $MEMORY_STATUS"
              echo "  📊 Usage: $MEMORY_USAGE% ($USED_MB MB / $TOTAL_MB MB)"
              echo "  💿 Available: $MEMORY_AVAILABLE% ($AVAILABLE_MB MB)"
              echo ""
            ''}
            
            # Network monitoring
            ${optionalString config.dotfiles.context.resourceMonitoring.networkMonitoring.enable ''
              echo "🌐 Network Analysis:"
              
              # Basic connectivity test
              if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
                CONNECTIVITY="online"
                CONN_EMOJI="🌐"
                
                # Latency test
                LATENCY=$(ping -c 3 8.8.8.8 2>/dev/null | tail -1 | awk -F'/' '{print $5}' | cut -d'.' -f1 || echo "999")
                
                # Determine network quality
                if [[ "$LATENCY" =~ ^[0-9]+$ ]]; then
                  if [[ "$LATENCY" -lt ${toString config.dotfiles.context.resourceMonitoring.networkMonitoring.qualityThresholds.excellent} ]]; then
                    NETWORK_QUALITY="excellent"
                    QUAL_EMOJI="💚"
                  elif [[ "$LATENCY" -lt ${toString config.dotfiles.context.resourceMonitoring.networkMonitoring.qualityThresholds.good} ]]; then
                    NETWORK_QUALITY="good"
                    QUAL_EMOJI="💛"
                  elif [[ "$LATENCY" -lt ${toString config.dotfiles.context.resourceMonitoring.networkMonitoring.qualityThresholds.moderate} ]]; then
                    NETWORK_QUALITY="moderate"
                    QUAL_EMOJI="🧡"
                  elif [[ "$LATENCY" -lt ${toString config.dotfiles.context.resourceMonitoring.networkMonitoring.qualityThresholds.poor} ]]; then
                    NETWORK_QUALITY="poor"
                    QUAL_EMOJI="❤️"
                  else
                    NETWORK_QUALITY="very_poor"
                    QUAL_EMOJI="🚨"
                  fi
                  NETWORK_LATENCY="$LATENCY"
                else
                  NETWORK_QUALITY="unknown"
                  QUAL_EMOJI="❓"
                fi
                
                echo "  $CONN_EMOJI Status: $CONNECTIVITY"
                echo "  $QUAL_EMOJI Quality: $NETWORK_QUALITY (${LATENCY}ms)"
                
                # Test specific services
                echo "  📡 Service connectivity:"
                ping -c 1 github.com >/dev/null 2>&1 && echo "    ✅ GitHub: reachable" || echo "    ❌ GitHub: unreachable"
                ping -c 1 google.com >/dev/null 2>&1 && echo "    ✅ Google: reachable" || echo "    ❌ Google: unreachable"
                
              else
                CONNECTIVITY="offline"
                NETWORK_QUALITY="unavailable"
                echo "  📡 Status: offline or limited"
              fi
              echo ""
            ''}
            
            # Storage monitoring
            ${optionalString config.dotfiles.context.resourceMonitoring.storageMonitoring.enable ''
              echo "💿 Storage Analysis:"
              
              # Main disk analysis
              DISK_INFO=$(df -h / | tail -1)
              DISK_USAGE_PERCENT=$(echo "$DISK_INFO" | awk '{print $5}' | tr -d '%')
              DISK_USED=$(echo "$DISK_INFO" | awk '{print $3}')
              DISK_AVAILABLE=$(echo "$DISK_INFO" | awk '{print $4}')
              DISK_TOTAL=$(echo "$DISK_INFO" | awk '{print $2}')
              
              STORAGE_AVAILABLE=$(( 100 - DISK_USAGE_PERCENT ))
              STORAGE_USAGE="$DISK_USAGE_PERCENT"
              
              # Determine storage status
              if [[ "$STORAGE_AVAILABLE" -gt ${toString config.dotfiles.context.resourceMonitoring.storageMonitoring.spaceThresholds.available} ]]; then
                STORAGE_STATUS="excellent"
                STORAGE_EMOJI="💚"
              elif [[ "$STORAGE_AVAILABLE" -gt ${toString config.dotfiles.context.resourceMonitoring.storageMonitoring.spaceThresholds.moderate} ]]; then
                STORAGE_STATUS="good"
                STORAGE_EMOJI="💛"
              elif [[ "$STORAGE_AVAILABLE" -gt ${toString config.dotfiles.context.resourceMonitoring.storageMonitoring.spaceThresholds.low} ]]; then
                STORAGE_STATUS="moderate"
                STORAGE_EMOJI="🧡"
              elif [[ "$STORAGE_AVAILABLE" -gt ${toString config.dotfiles.context.resourceMonitoring.storageMonitoring.spaceThresholds.critical} ]]; then
                STORAGE_STATUS="low"
                STORAGE_EMOJI="❤️"
              else
                STORAGE_STATUS="critical"
                STORAGE_EMOJI="🚨"
              fi
              
              echo "  $STORAGE_EMOJI Status: $STORAGE_STATUS"
              echo "  📊 Usage: $STORAGE_USAGE% ($DISK_USED / $DISK_TOTAL)"
              echo "  💿 Available: $STORAGE_AVAILABLE% ($DISK_AVAILABLE)"
              
              # Check other important directories
              if [[ -d "/tmp" ]]; then
                TMP_USAGE=$(df -h /tmp | tail -1 | awk '{print $5}' | tr -d '%')
                echo "  📁 /tmp usage: $TMP_USAGE%"
              fi
              
              if [[ "$(uname)" == "Darwin" ]] && [[ -d "/System/Volumes/Data" ]]; then
                DATA_USAGE=$(df -h /System/Volumes/Data | tail -1 | awk '{print $5}' | tr -d '%')
                echo "  📁 Data volume: $DATA_USAGE%"
              fi
              echo ""
            ''}
            
            # Overall system assessment
            echo "📊 System Health Assessment:"
            
            # Calculate overall health score
            HEALTH_SCORE=100
            ALERTS=()
            
            # Battery impact
            if [[ "$BATTERY_LEVEL" != "unknown" ]] && [[ "$BATTERY_LEVEL" =~ ^[0-9]+$ ]]; then
              if [[ "$BATTERY_LEVEL" -lt ${toString config.dotfiles.context.resourceMonitoring.batteryMonitoring.thresholds.critical} ]]; then
                HEALTH_SCORE=$((HEALTH_SCORE - 30))
                ALERTS+=("🔋 Battery critically low: $BATTERY_LEVEL%")
              elif [[ "$BATTERY_LEVEL" -lt ${toString config.dotfiles.context.resourceMonitoring.batteryMonitoring.thresholds.low} ]]; then
                HEALTH_SCORE=$((HEALTH_SCORE - 15))
                ALERTS+=("🔋 Battery low: $BATTERY_LEVEL%")
              fi
            fi
            
            # CPU impact
            if [[ "$CPU_USAGE" != "unknown" ]] && [[ "$CPU_USAGE" =~ ^[0-9]+$ ]]; then
              if [[ "$CPU_USAGE" -gt ${toString config.dotfiles.context.resourceMonitoring.cpuMonitoring.thresholds.heavy} ]]; then
                HEALTH_SCORE=$((HEALTH_SCORE - 25))
                ALERTS+=("🖥️  CPU usage critical: $CPU_USAGE%")
              elif [[ "$CPU_USAGE" -gt ${toString config.dotfiles.context.resourceMonitoring.cpuMonitoring.thresholds.moderate} ]]; then
                HEALTH_SCORE=$((HEALTH_SCORE - 10))
              fi
            fi
            
            # Memory impact
            if [[ "$MEMORY_AVAILABLE" != "unknown" ]] && [[ "$MEMORY_AVAILABLE" =~ ^[0-9]+$ ]]; then
              if [[ "$MEMORY_AVAILABLE" -lt ${toString config.dotfiles.context.resourceMonitoring.memoryMonitoring.thresholds.critical} ]]; then
                HEALTH_SCORE=$((HEALTH_SCORE - 25))
                ALERTS+=("💾 Memory critically low: $MEMORY_AVAILABLE% available")
              elif [[ "$MEMORY_AVAILABLE" -lt ${toString config.dotfiles.context.resourceMonitoring.memoryMonitoring.thresholds.high} ]]; then
                HEALTH_SCORE=$((HEALTH_SCORE - 10))
              fi
            fi
            
            # Storage impact
            if [[ "$STORAGE_AVAILABLE" != "unknown" ]] && [[ "$STORAGE_AVAILABLE" =~ ^[0-9]+$ ]]; then
              if [[ "$STORAGE_AVAILABLE" -lt ${toString config.dotfiles.context.resourceMonitoring.storageMonitoring.spaceThresholds.critical} ]]; then
                HEALTH_SCORE=$((HEALTH_SCORE - 20))
                ALERTS+=("💿 Storage critically low: $STORAGE_AVAILABLE% available")
              elif [[ "$STORAGE_AVAILABLE" -lt ${toString config.dotfiles.context.resourceMonitoring.storageMonitoring.spaceThresholds.low} ]]; then
                HEALTH_SCORE=$((HEALTH_SCORE - 10))
              fi
            fi
            
            # Network impact
            if [[ "$NETWORK_QUALITY" == "poor" ]] || [[ "$NETWORK_QUALITY" == "very_poor" ]]; then
              HEALTH_SCORE=$((HEALTH_SCORE - 15))
              ALERTS+=("🌐 Network quality poor: ${LATENCY}ms latency")
            elif [[ "$CONNECTIVITY" == "offline" ]]; then
              HEALTH_SCORE=$((HEALTH_SCORE - 20))
              ALERTS+=("🌐 Network offline")
            fi
            
            # Overall health classification
            if [[ "$HEALTH_SCORE" -gt 85 ]]; then
              OVERALL_HEALTH="excellent"
              HEALTH_EMOJI="💚"
            elif [[ "$HEALTH_SCORE" -gt 70 ]]; then
              OVERALL_HEALTH="good"
              HEALTH_EMOJI="💛"
            elif [[ "$HEALTH_SCORE" -gt 50 ]]; then
              OVERALL_HEALTH="moderate"
              HEALTH_EMOJI="🧡"
            elif [[ "$HEALTH_SCORE" -gt 30 ]]; then
              OVERALL_HEALTH="poor"
              HEALTH_EMOJI="❤️"
            else
              OVERALL_HEALTH="critical"
              HEALTH_EMOJI="🚨"
            fi
            
            echo "  $HEALTH_EMOJI Overall: $OVERALL_HEALTH (score: $HEALTH_SCORE/100)"
            
            # Show alerts
            if [[ ''${#ALERTS[@]} -gt 0 ]]; then
              echo ""
              echo "⚠️  Active Alerts:"
              for alert in "''${ALERTS[@]}"; do
                echo "  $alert"
              done
            fi
            
            # Save monitoring data
            CONTEXT_DIR="$HOME/.local/share/dotfiles-context/resources"
            mkdir -p "$CONTEXT_DIR"
            
            TIMESTAMP=$(date +%s)
            CONTEXT_FILE="$CONTEXT_DIR/resources-$TIMESTAMP.json"
            
            # Create JSON output
            cat > "$CONTEXT_FILE" << EOF
{
  "timestamp": $TIMESTAMP,
  "detection_time": "$(date)",
  "battery": {
    "level": "''${BATTERY_LEVEL:-null}",
    "status": "$BATTERY_STATUS",
    "power_source": "$POWER_SOURCE"
  },
  "cpu": {
    "usage": "''${CPU_USAGE:-null}",
    "temperature": "''${CPU_TEMP:-null}",
    "load_level": "$CPU_LOAD",
    "cores": "''${CORES:-null}"
  },
  "memory": {
    "usage_percent": "''${MEMORY_USAGE:-null}",
    "available_percent": "''${MEMORY_AVAILABLE:-null}",
    "status": "$MEMORY_STATUS"
  },
  "network": {
    "connectivity": "$CONNECTIVITY",
    "quality": "$NETWORK_QUALITY",
    "latency": "''${NETWORK_LATENCY:-null}"
  },
  "storage": {
    "usage_percent": "''${STORAGE_USAGE:-null}",
    "available_percent": "''${STORAGE_AVAILABLE:-null}",
    "status": "$STORAGE_STATUS"
  },
  "overall": {
    "health": "$OVERALL_HEALTH",
    "score": $HEALTH_SCORE,
    "alerts": [$(printf '"%s",' "''${ALERTS[@]}" | sed 's/,$//')]]
  }
}
EOF
            
            case "$OUTPUT_FORMAT" in
              "summary")
                echo ""
                echo "📋 Resource Summary:"
                echo "  🔋 Battery: $BATTERY_LEVEL% ($BATTERY_STATUS)"
                echo "  🖥️  CPU: $CPU_USAGE% ($CPU_LOAD)"
                echo "  💾 Memory: $MEMORY_USAGE% used ($MEMORY_STATUS)"
                echo "  🌐 Network: $NETWORK_QUALITY ($CONNECTIVITY)"
                echo "  💿 Storage: $STORAGE_USAGE% used ($STORAGE_STATUS)"
                echo "  📊 Health: $OVERALL_HEALTH ($HEALTH_SCORE/100)"
                ;;
                
              "json")
                echo ""
                echo "💾 Resource data saved to: $CONTEXT_FILE"
                ;;
                
              "alert")
                if [[ ''${#ALERTS[@]} -gt 0 ]]; then
                  echo ""
                  echo "🚨 Critical Resource Alerts:"
                  for alert in "''${ALERTS[@]}"; do
                    echo "  $alert"
                  done
                  exit 1
                else
                  echo ""
                  echo "✅ All resources within normal parameters"
                  exit 0
                fi
                ;;
            esac
            ;;
            
          "continuous")
            echo "🔄 Starting continuous monitoring for $DURATION seconds..."
            echo ""
            
            for ((i=1; i<=DURATION; i++)); do
              echo "[$i/$DURATION] $(date)"
              
              # Quick resource check
              if [[ "$(uname)" == "Darwin" ]]; then
                BATTERY=$(pmset -g batt | grep -Eo "[0-9]+%" | head -1 | tr -d '%' || echo "?")
                CPU=$(top -l 1 | grep "CPU usage" | awk '{print $3}' | tr -d '%' || echo "?")
              else
                BATTERY=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1 || echo "?")
                CPU=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$3+$4)} END {print int(usage)}' || echo "?")
              fi
              
              MEMORY=$(free | grep Mem | awk '{print int($3/$2*100)}' 2>/dev/null || vm_stat | awk '/Pages active/ {active=$3} /Pages inactive/ {inactive=$3} /Pages free/ {free=$3} /Pages wired/ {wired=$4} END {total=active+inactive+free+wired; used=active+wired; print int(used/total*100)}' || echo "?")
              
              echo "  🔋 $BATTERY%  🖥️ $CPU%  💾 $MEMORY%"
              echo "---"
              
              sleep 1
            done
            ;;
            
          *)
            echo "Usage: context-monitor-resources <action> [duration] [format]"
            echo ""
            echo "Actions:"
            echo "  status        - Current resource status (default)"
            echo "  monitor       - Detailed monitoring"
            echo "  continuous    - Continuous monitoring for [duration] seconds"
            echo "  alert         - Check for critical alerts"
            echo ""
            echo "Formats:"
            echo "  summary       - Human-readable summary (default)"
            echo "  json          - JSON output with data storage"
            echo "  detailed      - Detailed analysis"
            echo "  alert         - Alert-only output"
            ;;
        esac
      '')
      
      # Resource optimization suggestions
      (writeShellScriptBin "context-optimize-resources" ''
        #!/bin/bash
        
        # Resource optimization suggestions
        
        set -euo pipefail
        
        RESOURCE_TYPE="''${1:-all}"
        
        echo "⚡ Resource Optimization Suggestions"
        echo "==================================="
        echo "Target: $RESOURCE_TYPE"
        echo ""
        
        case "$RESOURCE_TYPE" in
          "battery"|"all")
            echo "🔋 Battery Optimization:"
            
            if [[ "$(uname)" == "Darwin" ]]; then
              BATTERY_LEVEL=$(pmset -g batt | grep -Eo "[0-9]+%" | head -1 | tr -d '%' || echo "100")
              
              if [[ "$BATTERY_LEVEL" -lt 30 ]]; then
                echo "  📱 Enable Low Power Mode"
                echo "  💡 Reduce screen brightness"
                echo "  📶 Disable unnecessary wireless features"
                echo "  🔇 Reduce audio volume"
                echo "  ⏰ Set aggressive sleep timers"
              elif [[ "$BATTERY_LEVEL" -lt 60 ]]; then
                echo "  💻 Switch to power-saving CPU governor"
                echo "  🌙 Enable dark mode to save OLED power"
                echo "  📊 Close unnecessary applications"
              else
                echo "  ✅ Battery level sufficient - no optimization needed"
              fi
            fi
            echo ""
            ;;
        esac
        
        case "$RESOURCE_TYPE" in
          "cpu"|"all")
            echo "🖥️  CPU Optimization:"
            
            # Find high-CPU processes
            echo "  📊 Top CPU consumers:"
            if [[ "$(uname)" == "Darwin" ]]; then
              ps aux | sort -rn -k3 | head -5 | awk '{print "    " $3"% " $11}'
            else
              ps aux | sort -rn -k3 | head -5 | awk '{print "    " $3"% " $11}'
            fi
            
            echo "  💡 Suggestions:"
            echo "    • Close unnecessary applications"
            echo "    • Use Activity Monitor to identify resource hogs"
            echo "    • Consider background process management"
            echo ""
            ;;
        esac
        
        case "$RESOURCE_TYPE" in
          "memory"|"all")
            echo "💾 Memory Optimization:"
            
            # Memory usage analysis
            if [[ "$(uname)" == "Darwin" ]]; then
              echo "  🧹 Memory cleanup suggestions:"
              echo "    • Restart memory-intensive applications"
              echo "    • Clear browser caches"
              echo "    • Use 'sudo purge' to clear system caches"
            else
              echo "  🧹 Memory cleanup suggestions:"
              echo "    • Clear page cache: echo 1 | sudo tee /proc/sys/vm/drop_caches"
              echo "    • Restart memory-intensive applications"
              echo "    • Check for memory leaks in running processes"
            fi
            echo ""
            ;;
        esac
        
        case "$RESOURCE_TYPE" in
          "storage"|"all")
            echo "💿 Storage Optimization:"
            
            echo "  🧹 Cleanup suggestions:"
            echo "    • Empty trash/recycle bin"
            echo "    • Clear browser downloads and caches"
            echo "    • Remove old log files"
            echo "    • Clean development build artifacts"
            echo "    • Use storage analysis tools"
            
            if [[ "$(uname)" == "Darwin" ]]; then
              echo "    • Enable 'Optimize Storage' in Apple menu"
              echo "    • Use 'About This Mac > Storage > Optimize' recommendations"
            fi
            echo ""
            ;;
        esac
        
        case "$RESOURCE_TYPE" in
          "network"|"all")
            echo "🌐 Network Optimization:"
            
            echo "  📡 Connection improvements:"
            echo "    • Move closer to Wi-Fi router"
            echo "    • Use 5GHz Wi-Fi band if available"
            echo "    • Close bandwidth-intensive applications"
            echo "    • Consider wired connection for critical tasks"
            echo "    • Check for background updates"
            echo ""
            ;;
        esac
      '')
      
      # Resource alerts checker
      (writeShellScriptBin "context-check-alerts" ''
        #!/bin/bash
        
        # Check for resource alerts
        
        set -euo pipefail
        
        ALERT_LEVEL="''${1:-warning}"  # info, warning, critical
        
        echo "🚨 Resource Alert Check"
        echo "======================"
        echo "Alert level: $ALERT_LEVEL"
        echo ""
        
        ALERTS_FOUND=0
        
        # Battery alerts
        ${optionalString config.dotfiles.context.resourceMonitoring.batteryMonitoring.enable ''
          if [[ "$(uname)" == "Darwin" ]] && command -v pmset >/dev/null 2>&1; then
            BATTERY_LEVEL=$(pmset -g batt | grep -Eo "[0-9]+%" | head -1 | tr -d '%' || echo "100")
            
            if [[ "$BATTERY_LEVEL" -lt ${toString config.dotfiles.context.resourceMonitoring.batteryMonitoring.thresholds.critical} ]]; then
              echo "🚨 CRITICAL: Battery at $BATTERY_LEVEL% - immediate charging recommended"
              ((ALERTS_FOUND++))
            elif [[ "$BATTERY_LEVEL" -lt ${toString config.dotfiles.context.resourceMonitoring.batteryMonitoring.thresholds.low} ]] && [[ "$ALERT_LEVEL" != "critical" ]]; then
              echo "⚠️  WARNING: Battery at $BATTERY_LEVEL% - consider charging soon"
              ((ALERTS_FOUND++))
            fi
          fi
        ''}
        
        # Storage alerts
        ${optionalString config.dotfiles.context.resourceMonitoring.storageMonitoring.enable ''
          DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
          DISK_AVAILABLE=$(( 100 - DISK_USAGE ))
          
          if [[ "$DISK_AVAILABLE" -lt ${toString config.dotfiles.context.resourceMonitoring.storageMonitoring.spaceThresholds.critical} ]]; then
            echo "🚨 CRITICAL: Storage at $DISK_USAGE% full - cleanup required immediately"
            ((ALERTS_FOUND++))
          elif [[ "$DISK_AVAILABLE" -lt ${toString config.dotfiles.context.resourceMonitoring.storageMonitoring.spaceThresholds.low} ]] && [[ "$ALERT_LEVEL" != "critical" ]]; then
            echo "⚠️  WARNING: Storage at $DISK_USAGE% full - cleanup recommended"
            ((ALERTS_FOUND++))
          fi
        ''}
        
        if [[ "$ALERTS_FOUND" -eq 0 ]]; then
          echo "✅ No resource alerts at $ALERT_LEVEL level"
          exit 0
        else
          echo ""
          echo "Found $ALERTS_FOUND resource alerts"
          exit 1
        fi
      '')
    ];
  };
}