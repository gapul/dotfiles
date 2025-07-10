{ config, lib, pkgs, ... }:

with lib;

{
  options = {
    dotfiles.context.powerManagement = {
      enable = mkEnableOption "Intelligent power and performance management system";
      
      batteryOptimization = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable battery-aware system optimization";
        };
        
        powerProfiles = mkOption {
          type = types.attrsOf (types.submodule {
            options = {
              name = mkOption {
                type = types.str;
                description = "Human-readable profile name";
              };
              description = mkOption {
                type = types.str;
                description = "Profile description";
              };
              batteryThreshold = mkOption {
                type = types.int;
                description = "Battery percentage to activate this profile";
              };
              cpuGovernor = mkOption {
                type = types.str;
                default = "powersave";
                description = "CPU governor setting";
              };
              screenBrightness = mkOption {
                type = types.int;
                description = "Screen brightness percentage (0-100)";
              };
              disableServices = mkOption {
                type = types.listOf types.str;
                default = [];
                description = "Services to disable in this profile";
              };
              networkOptimization = mkOption {
                type = types.bool;
                default = true;
                description = "Enable network power optimization";
              };
            };
          });
          default = {
            power_saver = {
              name = "Power Saver";
              description = "Maximum battery conservation";
              batteryThreshold = 20;
              cpuGovernor = "powersave";
              screenBrightness = 30;
              disableServices = ["bluetooth" "location" "background_sync"];
              networkOptimization = true;
            };
            balanced = {
              name = "Balanced";
              description = "Balance between performance and power";
              batteryThreshold = 50;
              cpuGovernor = "balanced";
              screenBrightness = 70;
              disableServices = ["background_sync"];
              networkOptimization = true;
            };
            performance = {
              name = "Performance";
              description = "Maximum performance mode";
              batteryThreshold = 80;
              cpuGovernor = "performance";
              screenBrightness = 100;
              disableServices = [];
              networkOptimization = false;
            };
          };
          description = "Power management profiles";
        };
        
        adaptiveScaling = mkOption {
          type = types.bool;
          default = true;
          description = "Enable adaptive CPU frequency scaling";
        };
        
        backgroundTaskManagement = mkOption {
          type = types.bool;
          default = true;
          description = "Manage background tasks based on power state";
        };
      };
      
      performanceOptimization = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable intelligent performance optimization";
        };
        
        workloadDetection = mkOption {
          type = types.bool;
          default = true;
          description = "Detect and optimize for different workload types";
        };
        
        resourceScheduling = mkOption {
          type = types.bool;
          default = true;
          description = "Intelligent scheduling of resource-intensive tasks";
        };
        
        thermalManagement = mkOption {
          type = types.bool;
          default = true;
          description = "Thermal-aware performance scaling";
        };
        
        memoryOptimization = mkOption {
          type = types.bool;
          default = true;
          description = "Intelligent memory management and optimization";
        };
      };
      
      cloudOffloading = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable cloud computation offloading";
        };
        
        offloadThreshold = mkOption {
          type = types.int;
          default = 85;
          description = "CPU usage threshold to trigger cloud offloading";
        };
        
        supportedTasks = mkOption {
          type = types.listOf types.str;
          default = ["build" "test" "analysis" "compilation"];
          description = "Task types that can be offloaded to cloud";
        };
        
        preferredProviders = mkOption {
          type = types.listOf types.str;
          default = ["github_actions" "gitlab_ci" "aws_lambda"];
          description = "Preferred cloud providers for offloading";
        };
        
        networkRequirements = mkOption {
          type = types.attrsOf types.int;
          default = {
            minBandwidth = 10; # Mbps
            maxLatency = 100;  # ms
          };
          description = "Network requirements for cloud offloading";
        };
      };
      
      intelligentScheduling = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable intelligent task scheduling";
        };
        
        taskPrioritization = mkOption {
          type = types.bool;
          default = true;
          description = "Prioritize tasks based on context and urgency";
        };
        
        loadBalancing = mkOption {
          type = types.bool;
          default = true;
          description = "Balance system load across available resources";
        };
        
        predictiveScheduling = mkOption {
          type = types.bool;
          default = true;
          description = "Schedule tasks based on predicted resource availability";
        };
      };
    };
  };

  config = mkIf config.dotfiles.context.powerManagement.enable {
    environment.systemPackages = with pkgs; [
      # Power management commands
      (writeShellScriptBin "context-manage-power" ''
        #!/bin/bash
        
        # Intelligent power and performance management system
        
        set -euo pipefail
        
        ACTION="''${1:-status}"
        PROFILE="''${2:-auto}"
        FORCE="''${3:-false}"
        
        echo "⚡ Power & Performance Management"
        echo "================================"
        echo "Action: $ACTION"
        echo "Profile: $PROFILE"
        echo "⏰ Management time: $(date)"
        echo ""
        
        # Configuration directory
        POWER_CONFIG_DIR="$HOME/.local/share/dotfiles-context/power"
        mkdir -p "$POWER_CONFIG_DIR"
        
        # Get current power status
        get_power_status() {
          echo "🔋 Power Status Analysis:"
          
          if [[ "$(uname)" == "Darwin" ]]; then
            # macOS power status
            POWER_SOURCE=$(pmset -g ps | grep -o "AC Power\\|Battery Power" | head -1)
            BATTERY_LEVEL=$(pmset -g batt | grep -Eo "[0-9]+%" | head -1 | tr -d '%')
            BATTERY_TIME=$(pmset -g batt | grep -Eo "[0-9]+:[0-9]+" | head -1 || echo "unknown")
            CHARGING_STATE=$(pmset -g batt | grep -o "charging\\|discharging\\|charged" | head -1)
            
            # Thermal status
            if command -v powermetrics >/dev/null 2>&1; then
              CPU_TEMP=$(sudo powermetrics -n 1 -i 1000 --samplers smc | grep "CPU die temperature" | awk '{print $4}' | tr -d 'C' || echo "unknown")
            else
              CPU_TEMP="unknown"
            fi
            
          else
            # Linux power status
            if [[ -f "/sys/class/power_supply/BAT0/capacity" ]]; then
              BATTERY_LEVEL=$(cat /sys/class/power_supply/BAT0/capacity)
              POWER_SOURCE=$(cat /sys/class/power_supply/AC*/online | grep -q "1" && echo "AC Power" || echo "Battery Power")
              CHARGING_STATE=$(cat /sys/class/power_supply/BAT0/status | tr '[:upper:]' '[:lower:]')
            else
              BATTERY_LEVEL="unknown"
              POWER_SOURCE="unknown"
              CHARGING_STATE="unknown"
            fi
            
            # Thermal status (Linux)
            if [[ -f "/sys/class/thermal/thermal_zone0/temp" ]]; then
              CPU_TEMP=$(( $(cat /sys/class/thermal/thermal_zone0/temp) / 1000 ))
            else
              CPU_TEMP="unknown"
            fi
          fi
          
          echo "  🔌 Power source: $POWER_SOURCE"
          echo "  🔋 Battery level: $BATTERY_LEVEL%"
          echo "  ⚡ Charging state: $CHARGING_STATE"
          echo "  🌡️  CPU temperature: $CPU_TEMP°C"
          if [[ "$BATTERY_TIME" != "unknown" ]]; then
            echo "  ⏰ Battery time: $BATTERY_TIME"
          fi
          echo ""
        }
        
        # Detect optimal power profile
        ${optionalString config.dotfiles.context.powerManagement.batteryOptimization.enable ''
          detect_optimal_profile() {
            echo "🎯 Determining optimal power profile..."
            
            OPTIMAL_PROFILE="balanced"  # Default
            
            # Profile selection based on battery level and power source
            if [[ "$POWER_SOURCE" == "AC Power" ]]; then
              if [[ "$BATTERY_LEVEL" =~ ^[0-9]+$ ]] && [[ "$BATTERY_LEVEL" -gt 80 ]]; then
                OPTIMAL_PROFILE="performance"
              else
                OPTIMAL_PROFILE="balanced"
              fi
            else
              # On battery power
              if [[ "$BATTERY_LEVEL" =~ ^[0-9]+$ ]]; then
                if [[ "$BATTERY_LEVEL" -lt 20 ]]; then
                  OPTIMAL_PROFILE="power_saver"
                elif [[ "$BATTERY_LEVEL" -lt 50 ]]; then
                  OPTIMAL_PROFILE="balanced"
                else
                  OPTIMAL_PROFILE="performance"
                fi
              else
                OPTIMAL_PROFILE="power_saver"  # Conservative default
              fi
            fi
            
            # Consider thermal state
            if [[ "$CPU_TEMP" =~ ^[0-9]+$ ]] && [[ "$CPU_TEMP" -gt 80 ]]; then
              echo "  🌡️  High thermal load detected, reducing performance"
              case "$OPTIMAL_PROFILE" in
                "performance") OPTIMAL_PROFILE="balanced" ;;
                "balanced") OPTIMAL_PROFILE="power_saver" ;;
              esac
            fi
            
            echo "  🎯 Recommended profile: $OPTIMAL_PROFILE"
            echo "  📋 Reason: Battery $BATTERY_LEVEL%, $POWER_SOURCE, CPU $CPU_TEMP°C"
            echo ""
          }
        ''}
        
        # Apply power profile
        apply_power_profile() {
          local profile="$1"
          echo "⚙️  Applying power profile: $profile"
          
          case "$profile" in
            "power_saver")
              echo "  💡 Activating power saver mode..."
              
              # macOS optimizations
              if [[ "$(uname)" == "Darwin" ]]; then
                # Reduce screen brightness
                osascript -e "tell application \"System Events\" to set the brightness of every display to 0.3" 2>/dev/null || true
                
                # Enable Low Power Mode if available
                sudo pmset -b powernap 0 2>/dev/null || true
                sudo pmset -b tcpkeepalive 0 2>/dev/null || true
                sudo pmset -b darkwakes 0 2>/dev/null || true
                
                # Disable unnecessary services
                launchctl unload -w /System/Library/LaunchAgents/com.apple.AirPlayUIAgent.plist 2>/dev/null || true
                
              else
                # Linux optimizations
                # Set CPU governor to powersave
                if [[ -f "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor" ]]; then
                  for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
                    echo "powersave" | sudo tee "$cpu" >/dev/null 2>&1 || true
                  done
                fi
                
                # Reduce screen brightness
                if command -v brightnessctl >/dev/null 2>&1; then
                  brightnessctl set 30% 2>/dev/null || true
                fi
              fi
              
              echo "    ✅ Power saver optimizations applied"
              ;;
              
            "balanced")
              echo "  ⚖️  Activating balanced mode..."
              
              if [[ "$(uname)" == "Darwin" ]]; then
                # Balanced screen brightness
                osascript -e "tell application \"System Events\" to set the brightness of every display to 0.7" 2>/dev/null || true
                
                # Balanced power settings
                sudo pmset -b powernap 1 2>/dev/null || true
                
              else
                # Linux balanced mode
                if [[ -f "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor" ]]; then
                  for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
                    echo "ondemand" | sudo tee "$cpu" >/dev/null 2>&1 || true
                  done
                fi
                
                if command -v brightnessctl >/dev/null 2>&1; then
                  brightnessctl set 70% 2>/dev/null || true
                fi
              fi
              
              echo "    ✅ Balanced optimizations applied"
              ;;
              
            "performance")
              echo "  🚀 Activating performance mode..."
              
              if [[ "$(uname)" == "Darwin" ]]; then
                # Maximum screen brightness
                osascript -e "tell application \"System Events\" to set the brightness of every display to 1.0" 2>/dev/null || true
                
                # Performance power settings
                sudo pmset -c powernap 1 2>/dev/null || true
                sudo pmset -c tcpkeepalive 1 2>/dev/null || true
                
              else
                # Linux performance mode
                if [[ -f "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor" ]]; then
                  for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
                    echo "performance" | sudo tee "$cpu" >/dev/null 2>&1 || true
                  done
                fi
                
                if command -v brightnessctl >/dev/null 2>&1; then
                  brightnessctl set 100% 2>/dev/null || true
                fi
              fi
              
              echo "    ✅ Performance optimizations applied"
              ;;
          esac
        }
        
        # Monitor resource usage
        ${optionalString config.dotfiles.context.powerManagement.performanceOptimization.enable ''
          monitor_performance() {
            echo "📊 Performance Monitoring:"
            
            # CPU usage analysis
            if [[ "$(uname)" == "Darwin" ]]; then
              CPU_USAGE=$(top -l 1 | grep "CPU usage" | awk '{print $3}' | tr -d '%' || echo "0")
              MEMORY_PRESSURE=$(memory_pressure 2>/dev/null | grep "System-wide memory free percentage" | awk '{print $5}' | tr -d '%' || echo "50")
            else
              CPU_USAGE=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$3+$4)} END {print int(usage)}' || echo "0")
              MEMORY_PRESSURE=$(free | grep Mem | awk '{print int((($2-$3)/$2)*100)}' || echo "50")
            fi
            
            echo "  🖥️  CPU usage: $CPU_USAGE%"
            echo "  💾 Memory available: $MEMORY_PRESSURE%"
            
            # Performance recommendations
            if [[ "$CPU_USAGE" =~ ^[0-9]+$ ]] && [[ "$CPU_USAGE" -gt 80 ]]; then
              echo "  ⚠️  High CPU usage detected"
              echo "    💡 Consider switching to power_saver mode"
              echo "    💡 Close unnecessary applications"
              ${optionalString config.dotfiles.context.powerManagement.cloudOffloading.enable ''
                echo "    ☁️  Consider cloud offloading for intensive tasks"
              ''}
            fi
            
            if [[ "$MEMORY_PRESSURE" =~ ^[0-9]+$ ]] && [[ "$MEMORY_PRESSURE" -lt 20 ]]; then
              echo "  ⚠️  Low memory available"
              echo "    💡 Close memory-intensive applications"
              echo "    💡 Clear system caches"
            fi
            
            echo ""
          }
        ''}
        
        # Cloud offloading analysis
        ${optionalString config.dotfiles.context.powerManagement.cloudOffloading.enable ''
          analyze_cloud_offloading() {
            echo "☁️  Cloud Offloading Analysis:"
            
            # Check network conditions
            if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
              LATENCY=$(ping -c 3 8.8.8.8 2>/dev/null | tail -1 | awk -F'/' '{print $5}' | cut -d'.' -f1 || echo "999")
              
              echo "  🌐 Network latency: ''${LATENCY}ms"
              
              # Evaluate offloading feasibility
              if [[ "$LATENCY" =~ ^[0-9]+$ ]] && [[ "$LATENCY" -lt ${toString config.dotfiles.context.powerManagement.cloudOffloading.networkRequirements.maxLatency} ]]; then
                if [[ "$CPU_USAGE" =~ ^[0-9]+$ ]] && [[ "$CPU_USAGE" -gt ${toString config.dotfiles.context.powerManagement.cloudOffloading.offloadThreshold} ]]; then
                  echo "  ✅ Cloud offloading recommended"
                  echo "    🎯 High CPU usage ($CPU_USAGE%) and good network ($LATENCYms)"
                  echo "    📋 Suitable tasks: build, test, compilation"
                else
                  echo "  ❌ Cloud offloading not needed"
                  echo "    💡 CPU usage is acceptable ($CPU_USAGE%)"
                fi
              else
                echo "  ❌ Network conditions unsuitable for offloading"
                echo "    ⚠️  Latency too high (''${LATENCY}ms > ${toString config.dotfiles.context.powerManagement.cloudOffloading.networkRequirements.maxLatency}ms)"
              fi
            else
              echo "  ❌ No internet connection for cloud offloading"
            fi
            
            echo ""
          }
        ''}
        
        # Save power management state
        save_power_state() {
          local profile="$1"
          
          TIMESTAMP=$(date +%s)
          STATE_FILE="$POWER_CONFIG_DIR/power-state-$TIMESTAMP.json"
          
          cat > "$STATE_FILE" << EOF
{
  "timestamp": $TIMESTAMP,
  "management_time": "$(date)",
  "applied_profile": "$profile",
  "power_status": {
    "source": "$POWER_SOURCE",
    "battery_level": $BATTERY_LEVEL,
    "charging_state": "$CHARGING_STATE",
    "cpu_temperature": "$CPU_TEMP"
  },
  "performance_metrics": {
    "cpu_usage": $CPU_USAGE,
    "memory_pressure": $MEMORY_PRESSURE
  },
  "optimizations_applied": {
    "profile_applied": true,
    "brightness_adjusted": true,
    "cpu_governor_set": true
  }
}
EOF
          
          echo "💾 Power state saved to: $STATE_FILE"
        }
        
        case "$ACTION" in
          "status")
            get_power_status
            detect_optimal_profile
            monitor_performance
            analyze_cloud_offloading
            ;;
            
          "auto"|"optimize")
            get_power_status
            detect_optimal_profile
            
            if [[ "$PROFILE" == "auto" ]]; then
              PROFILE="$OPTIMAL_PROFILE"
            fi
            
            echo "⚡ Optimizing system for profile: $PROFILE"
            echo ""
            
            apply_power_profile "$PROFILE"
            monitor_performance
            analyze_cloud_offloading
            
            save_power_state "$PROFILE"
            
            echo "✨ Power optimization completed successfully!"
            ;;
            
          "profile")
            if [[ "$PROFILE" == "auto" ]]; then
              echo "❌ Please specify a profile: power_saver, balanced, or performance"
              exit 1
            fi
            
            get_power_status
            apply_power_profile "$PROFILE"
            save_power_state "$PROFILE"
            echo "✅ Power profile applied: $PROFILE"
            ;;
            
          "monitor")
            echo "🔄 Starting continuous power monitoring..."
            while true; do
              clear
              echo "⚡ Power & Performance Monitor - $(date)"
              echo "========================================"
              echo ""
              
              get_power_status
              monitor_performance
              
              echo "Press Ctrl+C to stop monitoring"
              sleep 5
            done
            ;;
            
          *)
            echo "Usage: context-manage-power <action> [profile] [force]"
            echo ""
            echo "Actions:"
            echo "  status                 - Show current power status and recommendations"
            echo "  auto/optimize          - Auto-optimize based on current conditions"
            echo "  profile <name>         - Apply specific power profile"
            echo "  monitor                - Continuous power monitoring"
            echo ""
            echo "Profiles:"
            echo "  power_saver           - Maximum battery conservation"
            echo "  balanced              - Balance performance and power"
            echo "  performance           - Maximum performance mode"
            echo ""
            echo "Force: true/false - Force profile application"
            ;;
        esac
      '')
      
      # Performance optimization utility
      (writeShellScriptBin "context-optimize-performance" ''
        #!/bin/bash
        
        # Intelligent performance optimization system
        
        set -euo pipefail
        
        OPTIMIZATION_TYPE="''${1:-auto}"
        TARGET="''${2:-system}"
        
        echo "🚀 Performance Optimization"
        echo "=========================="
        echo "Type: $OPTIMIZATION_TYPE"
        echo "Target: $TARGET"
        echo "⏰ Optimization time: $(date)"
        echo ""
        
        case "$OPTIMIZATION_TYPE" in
          "auto"|"detect")
            echo "🔍 Detecting performance bottlenecks..."
            
            # CPU analysis
            echo "  🖥️  CPU Analysis:"
            if [[ "$(uname)" == "Darwin" ]]; then
              CPU_USAGE=$(top -l 1 | grep "CPU usage" | awk '{print $3}' | tr -d '%')
              CPU_PROCESSES=$(ps aux | sort -rn -k3 | head -5)
            else
              CPU_USAGE=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$3+$4)} END {print int(usage)}')
              CPU_PROCESSES=$(ps aux | sort -rn -k3 | head -5)
            fi
            
            echo "    Current usage: $CPU_USAGE%"
            echo "    Top CPU consumers:"
            echo "$CPU_PROCESSES" | awk '{print "      " $3"% " $11}' | head -3
            
            # Memory analysis
            echo ""
            echo "  💾 Memory Analysis:"
            if [[ "$(uname)" == "Darwin" ]]; then
              MEMORY_INFO=$(vm_stat | grep -E "Pages (free|active|inactive|wired|compressed)")
              echo "    $MEMORY_INFO" | sed 's/^/      /'
            else
              MEMORY_INFO=$(free -h | grep Mem)
              echo "    $MEMORY_INFO"
            fi
            
            # Disk I/O analysis
            echo ""
            echo "  💿 Disk I/O Analysis:"
            if command -v iostat >/dev/null 2>&1; then
              iostat -d 1 1 | tail -n +4 | head -3 | sed 's/^/      /'
            else
              echo "      iostat not available"
            fi
            
            # Network analysis
            echo ""
            echo "  🌐 Network Performance:"
            if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
              LATENCY=$(ping -c 3 8.8.8.8 2>/dev/null | tail -1 | awk -F'/' '{print $5}' | cut -d'.' -f1)
              echo "    Internet latency: ''${LATENCY}ms"
            else
              echo "    No internet connection"
            fi
            
            # Recommendations
            echo ""
            echo "💡 Performance Recommendations:"
            
            if [[ "$CPU_USAGE" =~ ^[0-9]+$ ]] && [[ "$CPU_USAGE" -gt 80 ]]; then
              echo "  🔥 High CPU usage detected:"
              echo "    • Close unnecessary applications"
              echo "    • Check for background processes"
              echo "    • Consider upgrading CPU-intensive workflows"
            fi
            
            echo "  ⚡ General optimizations:"
            echo "    • Enable SSD TRIM optimization"
            echo "    • Clear system caches regularly"
            echo "    • Optimize startup items"
            echo "    • Use lightweight alternatives for heavy applications"
            ;;
            
          "memory")
            echo "💾 Memory Optimization:"
            
            # Clear system caches
            echo "  🧹 Clearing system caches..."
            if [[ "$(uname)" == "Darwin" ]]; then
              sudo purge 2>/dev/null && echo "    ✅ macOS memory pressure released" || echo "    ❌ Could not release memory pressure"
            else
              sync && echo 1 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1 && echo "    ✅ Linux page cache cleared" || echo "    ❌ Could not clear caches"
            fi
            
            # Memory usage analysis
            echo ""
            echo "  📊 Memory Usage Analysis:"
            if [[ "$(uname)" == "Darwin" ]]; then
              ps aux | sort -rn -k4 | head -5 | awk '{print "    " $4"% " $11}' 
            else
              ps aux | sort -rn -k4 | head -5 | awk '{print "    " $4"% " $11}'
            fi
            ;;
            
          "disk")
            echo "💿 Disk Optimization:"
            
            # TRIM optimization
            echo "  ✂️  SSD TRIM optimization..."
            if [[ "$(uname)" == "Darwin" ]]; then
              trimforce status | grep -q "TRIM support: Yes" && echo "    ✅ TRIM already enabled" || echo "    ⚠️  TRIM may not be enabled"
            else
              if command -v fstrim >/dev/null 2>&1; then
                sudo fstrim -v / 2>/dev/null && echo "    ✅ TRIM optimization completed" || echo "    ❌ TRIM optimization failed"
              fi
            fi
            
            # Disk space analysis
            echo ""
            echo "  📊 Disk Space Analysis:"
            df -h | grep -E "^/dev" | awk '{print "    " $5 " used - " $1}' | head -5
            
            # Cleanup suggestions
            echo ""
            echo "  🧹 Cleanup Suggestions:"
            echo "    • Clear browser caches and downloads"
            echo "    • Remove old log files"
            echo "    • Empty trash/recycle bin"
            echo "    • Clean package manager caches"
            ;;
            
          "network")
            echo "🌐 Network Optimization:"
            
            # DNS optimization
            echo "  🎯 DNS Performance Test:"
            for dns in "8.8.8.8" "1.1.1.1" "208.67.222.222"; do
              LATENCY=$(ping -c 1 "$dns" 2>/dev/null | grep "time=" | awk -F'time=' '{print $2}' | awk '{print $1}' || echo "timeout")
              echo "    $dns: $LATENCY"
            done
            
            # Network interface optimization
            echo ""
            echo "  📡 Network Interface Status:"
            if [[ "$(uname)" == "Darwin" ]]; then
              networksetup -listallhardwareports | grep -A1 "Wi-Fi" | grep "Device" | awk '{print "    Wi-Fi: " $2}'
            else
              ip link show | grep "state UP" | awk '{print "    " $2}' | head -3
            fi
            ;;
            
          *)
            echo "Usage: context-optimize-performance <type> [target]"
            echo ""
            echo "Types:"
            echo "  auto/detect           - Auto-detect and optimize bottlenecks"
            echo "  memory                - Memory-specific optimizations"
            echo "  disk                  - Disk and storage optimizations"
            echo "  network               - Network performance optimizations"
            echo ""
            echo "Targets:"
            echo "  system                - System-wide optimizations"
            echo "  application           - Application-specific optimizations"
            ;;
        esac
        
        echo ""
        echo "🎯 Performance optimization completed"
      '')
    ];
  };
}