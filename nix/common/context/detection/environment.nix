{ config, lib, pkgs, ... }:

with lib;

{
  options = {
    dotfiles.context.environmentDetection = {
      enable = mkEnableOption "Intelligent environment and context detection";
      
      timePatterns = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Work time pattern analysis and detection";
        };
        
        patterns = mkOption {
          type = types.attrsOf types.str;
          default = {
            morning = "06:00-12:00";
            afternoon = "12:00-18:00";
            evening = "18:00-24:00";
            night = "00:00-06:00";
          };
          description = "Time period definitions";
        };
        
        workingHours = mkOption {
          type = types.attrsOf types.str;
          default = {
            weekday = "09:00-18:00";
            weekend = "10:00-16:00";
          };
          description = "Standard working hours by day type";
        };
      };
      
      locationDetection = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Work location detection and classification";
        };
        
        methods = mkOption {
          type = types.listOf types.str;
          default = ["wifi_ssid" "network_profile" "external_devices" "timezone"];
          description = "Location detection methods to use";
        };
        
        locations = mkOption {
          type = types.attrsOf (types.submodule {
            options = {
              name = mkOption {
                type = types.str;
                description = "Human-readable location name";
              };
              wifi_patterns = mkOption {
                type = types.listOf types.str;
                default = [];
                description = "WiFi SSID patterns for this location";
              };
              device_patterns = mkOption {
                type = types.listOf types.str;
                default = [];
                description = "Connected device patterns";
              };
              timezone = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Expected timezone for this location";
              };
            };
          });
          default = {
            home = {
              name = "Home Office";
              wifi_patterns = ["home-*" "*-home" "MyWiFi"];
              device_patterns = ["Home-*" "*-Personal"];
              timezone = null;
            };
            office = {
              name = "Office";
              wifi_patterns = ["*-corp" "*-office" "Company*"];
              device_patterns = ["Office-*" "*-Work"];
              timezone = null;
            };
            cafe = {
              name = "Cafe/Public";
              wifi_patterns = ["*free*" "*guest*" "*public*"];
              device_patterns = [];
              timezone = null;
            };
          };
          description = "Predefined location profiles";
        };
      };
      
      situationDetection = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Work situation and context detection";
        };
        
        situations = mkOption {
          type = types.listOf types.str;
          default = [
            "focused_work" "meeting" "collaboration" "learning" 
            "debugging" "writing" "research" "break"
          ];
          description = "Supported work situations";
        };
        
        appPatterns = mkOption {
          type = types.attrsOf (types.listOf types.str);
          default = {
            meeting = ["zoom*" "*teams*" "*meet*" "*webex*" "skype*"];
            collaboration = ["slack*" "*discord*" "*telegram*" "notion*"];
            coding = ["*code*" "*vim*" "*emacs*" "cursor*" "zed*"];
            research = ["*browser*" "*firefox*" "*chrome*" "*safari*"];
            writing = ["*docs*" "*word*" "*pages*" "*obsidian*"];
            debugging = ["*debug*" "*console*" "*terminal*"];
          };
          description = "Application patterns for situation detection";
        };
      };
      
      activityTracking = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Track activity patterns for analysis";
        };
        
        trackKeyboard = mkOption {
          type = types.bool;
          default = true;
          description = "Track keyboard activity patterns";
        };
        
        trackMouse = mkOption {
          type = types.bool;
          default = true;
          description = "Track mouse activity patterns";
        };
        
        trackApplications = mkOption {
          type = types.bool;
          default = true;
          description = "Track application usage patterns";
        };
        
        privacyMode = mkOption {
          type = types.bool;
          default = true;
          description = "Enable privacy-conscious tracking (aggregated data only)";
        };
      };
    };
  };

  config = mkIf config.dotfiles.context.environmentDetection.enable {
    environment.systemPackages = with pkgs; [
      # Environment detection commands
      (writeShellScriptBin "context-detect-environment" ''
        #!/bin/bash
        
        # Intelligent environment and context detection
        
        set -euo pipefail
        
        ACTION="''${1:-detect}"
        OUTPUT_FORMAT="''${2:-summary}"  # summary, json, detailed
        
        echo "🌍 Environment Context Detection"
        echo "==============================="
        echo "Action: $ACTION"
        echo "⏰ Detection time: $(date)"
        echo ""
        
        # Initialize context data
        CONTEXT_DATA=""
        CURRENT_TIME=$(date +%H:%M)
        CURRENT_DAY=$(date +%A)
        CURRENT_DATE=$(date +%Y-%m-%d)
        
        case "$ACTION" in
          "detect"|"full")
            # Time pattern detection
            ${optionalString config.dotfiles.context.environmentDetection.timePatterns.enable ''
              echo "⏰ Time Context Analysis:"
              
              HOUR=$(date +%H)
              
              # Determine time period
              if [ "$HOUR" -ge 6 ] && [ "$HOUR" -lt 12 ]; then
                TIME_PERIOD="morning"
                TIME_EMOJI="🌅"
              elif [ "$HOUR" -ge 12 ] && [ "$HOUR" -lt 18 ]; then
                TIME_PERIOD="afternoon"
                TIME_EMOJI="☀️"
              elif [ "$HOUR" -ge 18 ] && [ "$HOUR" -lt 24 ]; then
                TIME_PERIOD="evening"
                TIME_EMOJI="🌆"
              else
                TIME_PERIOD="night"
                TIME_EMOJI="🌙"
              fi
              
              echo "  $TIME_EMOJI Time period: $TIME_PERIOD ($CURRENT_TIME)"
              echo "  📅 Day: $CURRENT_DAY"
              
              # Determine if it's working hours
              DOW=$(date +%u)  # 1=Monday, 7=Sunday
              if [ "$DOW" -le 5 ]; then
                DAY_TYPE="weekday"
                if [ "$HOUR" -ge 9 ] && [ "$HOUR" -lt 18 ]; then
                  WORK_TIME="working_hours"
                  WORK_EMOJI="💼"
                else
                  WORK_TIME="off_hours"
                  WORK_EMOJI="🏠"
                fi
              else
                DAY_TYPE="weekend"
                if [ "$HOUR" -ge 10 ] && [ "$HOUR" -lt 16 ]; then
                  WORK_TIME="light_work"
                  WORK_EMOJI="📝"
                else
                  WORK_TIME="personal_time"
                  WORK_EMOJI="🎮"
                fi
              fi
              
              echo "  $WORK_EMOJI Work context: $WORK_TIME ($DAY_TYPE)"
              echo ""
            ''}
            
            # Location detection
            ${optionalString config.dotfiles.context.environmentDetection.locationDetection.enable ''
              echo "📍 Location Analysis:"
              
              # WiFi network detection
              WIFI_SSID=""
              LOCATION_TYPE="unknown"
              LOCATION_CONFIDENCE=0
              
              if command -v networksetup >/dev/null 2>&1; then
                # macOS WiFi detection
                WIFI_SSID=$(networksetup -getairportnetwork en0 2>/dev/null | cut -d: -f2- | sed 's/^ *//' || echo "")
              elif command -v iwgetid >/dev/null 2>&1; then
                # Linux WiFi detection
                WIFI_SSID=$(iwgetid -r 2>/dev/null || echo "")
              fi
              
              if [ -n "$WIFI_SSID" ]; then
                echo "  📶 WiFi Network: $WIFI_SSID"
                
                # Location pattern matching
                case "$WIFI_SSID" in
                  *home*|*Home*|*personal*|MyWiFi)
                    LOCATION_TYPE="home"
                    LOCATION_CONFIDENCE=90
                    ;;
                  *corp*|*office*|*work*|*company*)
                    LOCATION_TYPE="office"
                    LOCATION_CONFIDENCE=85
                    ;;
                  *guest*|*public*|*free*|*cafe*)
                    LOCATION_TYPE="public"
                    LOCATION_CONFIDENCE=75
                    ;;
                  *)
                    LOCATION_TYPE="unknown"
                    LOCATION_CONFIDENCE=20
                    ;;
                esac
              else
                echo "  📶 WiFi: Not connected or unavailable"
                LOCATION_TYPE="offline"
              fi
              
              echo "  🏠 Location type: $LOCATION_TYPE (confidence: $LOCATION_CONFIDENCE%)"
              
              # Connected devices detection
              CONNECTED_DEVICES=""
              if command -v system_profiler >/dev/null 2>&1; then
                # macOS connected devices
                CONNECTED_DEVICES=$(system_profiler SPUSBDataType 2>/dev/null | grep -E "Product ID|Manufacturer" | wc -l)
              elif command -v lsusb >/dev/null 2>&1; then
                # Linux connected devices
                CONNECTED_DEVICES=$(lsusb 2>/dev/null | wc -l)
              fi
              
              if [ -n "$CONNECTED_DEVICES" ] && [ "$CONNECTED_DEVICES" -gt 0 ]; then
                echo "  🔌 Connected devices: $CONNECTED_DEVICES"
                
                # Adjust location confidence based on device count
                if [ "$CONNECTED_DEVICES" -gt 3 ]; then
                  # Likely a permanent workspace (home/office)
                  if [ "$LOCATION_TYPE" = "unknown" ]; then
                    LOCATION_TYPE="workspace"
                    LOCATION_CONFIDENCE=60
                  else
                    LOCATION_CONFIDENCE=$((LOCATION_CONFIDENCE + 10))
                  fi
                fi
              fi
              
              echo ""
            ''}
            
            # Situation detection
            ${optionalString config.dotfiles.context.environmentDetection.situationDetection.enable ''
              echo "🎯 Situation Analysis:"
              
              # Get currently running applications
              ACTIVE_APPS=""
              SITUATION="unknown"
              SITUATION_CONFIDENCE=0
              
              if command -v osascript >/dev/null 2>&1; then
                # macOS application detection
                ACTIVE_APPS=$(osascript -e 'tell application "System Events" to get name of (processes where background only is false)' 2>/dev/null | tr ',' '\n' | sed 's/^ *//' || echo "")
              elif command -v ps >/dev/null 2>&1; then
                # Linux application detection
                ACTIVE_APPS=$(ps aux --format comm --no-headers | sort -u || echo "")
              fi
              
              if [ -n "$ACTIVE_APPS" ]; then
                echo "  📱 Active applications detected: $(echo "$ACTIVE_APPS" | wc -w) apps"
                
                # Situation pattern matching
                MEETING_COUNT=0
                CODING_COUNT=0
                BROWSER_COUNT=0
                COMM_COUNT=0
                
                while IFS= read -r app; do
                  app_lower=$(echo "$app" | tr '[:upper:]' '[:lower:]')
                  
                  case "$app_lower" in
                    *zoom*|*teams*|*meet*|*webex*|*skype*)
                      ((MEETING_COUNT++))
                      ;;
                    *code*|*vim*|*emacs*|*cursor*|*zed*|*terminal*)
                      ((CODING_COUNT++))
                      ;;
                    *browser*|*firefox*|*chrome*|*safari*)
                      ((BROWSER_COUNT++))
                      ;;
                    *slack*|*discord*|*telegram*|*notion*)
                      ((COMM_COUNT++))
                      ;;
                  esac
                done <<< "$ACTIVE_APPS"
                
                # Determine primary situation
                if [ "$MEETING_COUNT" -gt 0 ]; then
                  SITUATION="meeting"
                  SITUATION_CONFIDENCE=90
                elif [ "$CODING_COUNT" -gt 1 ]; then
                  SITUATION="coding"
                  SITUATION_CONFIDENCE=85
                elif [ "$COMM_COUNT" -gt 0 ] && [ "$CODING_COUNT" -gt 0 ]; then
                  SITUATION="collaboration"
                  SITUATION_CONFIDENCE=80
                elif [ "$BROWSER_COUNT" -gt 0 ] && [ "$CODING_COUNT" -eq 0 ]; then
                  SITUATION="research"
                  SITUATION_CONFIDENCE=70
                else
                  SITUATION="general_work"
                  SITUATION_CONFIDENCE=50
                fi
                
                echo "  🎯 Detected situation: $SITUATION (confidence: $SITUATION_CONFIDENCE%)"
                echo "    📊 Analysis: meetings=$MEETING_COUNT, coding=$CODING_COUNT, browsing=$BROWSER_COUNT, communication=$COMM_COUNT"
              else
                echo "  ⚠️  No active applications detected"
                SITUATION="idle"
              fi
              
              echo ""
            ''}
            
            # Activity pattern analysis
            ${optionalString config.dotfiles.context.environmentDetection.activityTracking.enable ''
              echo "📈 Activity Pattern Analysis:"
              
              # Check for recent activity indicators
              ACTIVITY_LEVEL="unknown"
              
              # Check recent file modifications (proxy for activity)
              RECENT_FILES=0
              if [ -d "$HOME" ]; then
                RECENT_FILES=$(find "$HOME" -name ".*" -prune -o -type f -mmin -10 -print 2>/dev/null | wc -l)
              fi
              
              # Check shell history activity
              RECENT_COMMANDS=0
              if [ -f "$HOME/.zsh_history" ]; then
                RECENT_COMMANDS=$(tail -50 "$HOME/.zsh_history" 2>/dev/null | wc -l)
              fi
              
              # Determine activity level
              if [ "$RECENT_FILES" -gt 10 ] || [ "$RECENT_COMMANDS" -gt 20 ]; then
                ACTIVITY_LEVEL="high"
                ACTIVITY_EMOJI="🔥"
              elif [ "$RECENT_FILES" -gt 3 ] || [ "$RECENT_COMMANDS" -gt 10 ]; then
                ACTIVITY_LEVEL="moderate"
                ACTIVITY_EMOJI="📊"
              elif [ "$RECENT_FILES" -gt 0 ] || [ "$RECENT_COMMANDS" -gt 5 ]; then
                ACTIVITY_LEVEL="low"
                ACTIVITY_EMOJI="📉"
              else
                ACTIVITY_LEVEL="idle"
                ACTIVITY_EMOJI="😴"
              fi
              
              echo "  $ACTIVITY_EMOJI Activity level: $ACTIVITY_LEVEL"
              echo "  📁 Recent file changes: $RECENT_FILES (last 10 min)"
              echo "  ⌨️  Recent commands: $RECENT_COMMANDS (last session)"
              
              # Productivity context
              if [ "$ACTIVITY_LEVEL" = "high" ] && [ "$SITUATION" = "coding" ]; then
                PRODUCTIVITY="focused"
                PROD_EMOJI="🎯"
              elif [ "$ACTIVITY_LEVEL" = "moderate" ] && [ "$SITUATION" = "meeting" ]; then
                PRODUCTIVITY="collaborative"
                PROD_EMOJI="🤝"
              elif [ "$ACTIVITY_LEVEL" = "low" ] && [ "$TIME_PERIOD" = "afternoon" ]; then
                PRODUCTIVITY="break_time"
                PROD_EMOJI="☕"
              else
                PRODUCTIVITY="regular"
                PROD_EMOJI="💼"
              fi
              
              echo "  $PROD_EMOJI Productivity context: $PRODUCTIVITY"
              echo ""
            ''}
            
            # Environmental factors
            echo "🌡️  Environmental Context:"
            
            # Network connectivity
            if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
              CONNECTIVITY="online"
              CONN_EMOJI="🌐"
              
              # Test network speed (basic)
              SPEED_TEST=$(time (curl -s -o /dev/null https://httpbin.org/get) 2>&1 | grep real | awk '{print $2}' || echo "unknown")
              echo "  $CONN_EMOJI Network: online (response: $SPEED_TEST)"
            else
              CONNECTIVITY="offline"
              CONN_EMOJI="📡"
              echo "  $CONN_EMOJI Network: offline or limited"
            fi
            
            # Power status (macOS)
            if command -v pmset >/dev/null 2>&1; then
              POWER_SOURCE=$(pmset -g ps | grep -o "AC Power\|Battery Power" | head -1)
              BATTERY_LEVEL=$(pmset -g batt | grep -Eo "[0-9]+%" | head -1)
              
              if [ "$POWER_SOURCE" = "AC Power" ]; then
                POWER_EMOJI="🔌"
                echo "  $POWER_EMOJI Power: AC connected ($BATTERY_LEVEL)"
              else
                POWER_EMOJI="🔋"
                echo "  $POWER_EMOJI Power: Battery ($BATTERY_LEVEL)"
              fi
            else
              echo "  ⚡ Power: Status unavailable"
            fi
            
            # Display configuration
            if command -v system_profiler >/dev/null 2>&1; then
              DISPLAYS=$(system_profiler SPDisplaysDataType 2>/dev/null | grep -c "Display Type" || echo "1")
              echo "  🖥️  Displays: $DISPLAYS monitor(s)"
            elif command -v xrandr >/dev/null 2>&1; then
              DISPLAYS=$(xrandr --listmonitors 2>/dev/null | grep -c "Monitor" || echo "1")
              echo "  🖥️  Displays: $DISPLAYS monitor(s)"
            fi
            
            echo ""
            ;;
            
          "time")
            echo "⏰ Time Context:"
            echo "  Current: $CURRENT_TIME ($CURRENT_DAY)"
            echo "  Period: $TIME_PERIOD"
            echo "  Work context: $WORK_TIME"
            ;;
            
          "location")
            echo "📍 Location Context:"
            echo "  Type: $LOCATION_TYPE"
            echo "  WiFi: $WIFI_SSID"
            echo "  Confidence: $LOCATION_CONFIDENCE%"
            ;;
            
          "situation")
            echo "🎯 Situation Context:"
            echo "  Primary: $SITUATION"
            echo "  Confidence: $SITUATION_CONFIDENCE%"
            echo "  Activity: $ACTIVITY_LEVEL"
            ;;
            
          "summary")
            echo "📋 Environment Summary:"
            echo "  ⏰ Time: $TIME_PERIOD ($WORK_TIME)"
            echo "  📍 Location: $LOCATION_TYPE"
            echo "  🎯 Situation: $SITUATION"
            echo "  📈 Activity: $ACTIVITY_LEVEL"
            echo "  🌐 Network: $CONNECTIVITY"
            ;;
            
          *)
            echo "Usage: context-detect-environment <action> [format]"
            echo ""
            echo "Actions:"
            echo "  detect/full    - Complete environment analysis"
            echo "  time           - Time context only"
            echo "  location       - Location context only"
            echo "  situation      - Situation context only"
            echo "  summary        - Brief summary"
            echo ""
            echo "Formats:"
            echo "  summary        - Human-readable summary (default)"
            echo "  json           - JSON output"
            echo "  detailed       - Detailed analysis"
            ;;
        esac
        
        # Save context data
        CONTEXT_DIR="$HOME/.local/share/dotfiles-context/environment"
        mkdir -p "$CONTEXT_DIR"
        
        TIMESTAMP=$(date +%s)
        CONTEXT_FILE="$CONTEXT_DIR/context-$TIMESTAMP.json"
        
        # Create JSON output
        cat > "$CONTEXT_FILE" << EOF
{
  "timestamp": $TIMESTAMP,
  "detection_time": "$CURRENT_DATE $CURRENT_TIME",
  "time_context": {
    "period": "''${TIME_PERIOD:-unknown}",
    "work_time": "''${WORK_TIME:-unknown}",
    "day_type": "''${DAY_TYPE:-unknown}"
  },
  "location_context": {
    "type": "''${LOCATION_TYPE:-unknown}",
    "wifi_ssid": "''${WIFI_SSID:-}",
    "confidence": ''${LOCATION_CONFIDENCE:-0}
  },
  "situation_context": {
    "primary": "''${SITUATION:-unknown}",
    "confidence": ''${SITUATION_CONFIDENCE:-0},
    "activity_level": "''${ACTIVITY_LEVEL:-unknown}",
    "productivity": "''${PRODUCTIVITY:-unknown}"
  },
  "environment": {
    "connectivity": "''${CONNECTIVITY:-unknown}",
    "power_source": "''${POWER_SOURCE:-unknown}",
    "battery_level": "''${BATTERY_LEVEL:-unknown}",
    "displays": ''${DISPLAYS:-1}
  }
}
EOF
        
        echo ""
        echo "💾 Context saved to: $CONTEXT_FILE"
      '')
      
      # Location pattern learning
      (writeShellScriptBin "context-learn-location" ''
        #!/bin/bash
        
        # Learn and save location patterns
        
        set -euo pipefail
        
        LOCATION_NAME="''${1:-}"
        ACTION="''${2:-add}"
        
        if [ -z "$LOCATION_NAME" ]; then
          echo "Usage: context-learn-location <name> [add|remove|list]"
          echo ""
          echo "Examples:"
          echo "  context-learn-location home"
          echo "  context-learn-location office add"
          echo "  context-learn-location cafe"
          echo "  context-learn-location '' list"
          exit 1
        fi
        
        LOCATIONS_DIR="$HOME/.local/share/dotfiles-context/locations"
        mkdir -p "$LOCATIONS_DIR"
        
        case "$ACTION" in
          "add")
            echo "📍 Learning location pattern: $LOCATION_NAME"
            
            # Get current environment data
            WIFI_SSID=""
            if command -v networksetup >/dev/null 2>&1; then
              WIFI_SSID=$(networksetup -getairportnetwork en0 2>/dev/null | cut -d: -f2- | sed 's/^ *//' || echo "")
            elif command -v iwgetid >/dev/null 2>&1; then
              WIFI_SSID=$(iwgetid -r 2>/dev/null || echo "")
            fi
            
            # Get connected devices
            DEVICES=""
            if command -v system_profiler >/dev/null 2>&1; then
              DEVICES=$(system_profiler SPUSBDataType 2>/dev/null | grep "Product ID" | head -5 | sed 's/.*Product ID: //')
            fi
            
            # Get timezone
            TIMEZONE=$(date +%Z)
            
            # Save location profile
            LOCATION_FILE="$LOCATIONS_DIR/$LOCATION_NAME.json"
            cat > "$LOCATION_FILE" << EOF
{
  "name": "$LOCATION_NAME",
  "learned_date": "$(date)",
  "wifi_ssid": "$WIFI_SSID",
  "timezone": "$TIMEZONE",
  "devices": [$(echo "$DEVICES" | sed 's/^/"/' | sed 's/$/"/' | tr '\n' ',' | sed 's/,$//')],
  "usage_count": 1,
  "last_seen": "$(date)"
}
EOF
            
            echo "✅ Location '$LOCATION_NAME' learned successfully"
            echo "   WiFi: $WIFI_SSID"
            echo "   Timezone: $TIMEZONE"
            echo "   Saved to: $LOCATION_FILE"
            ;;
            
          "remove")
            LOCATION_FILE="$LOCATIONS_DIR/$LOCATION_NAME.json"
            if [ -f "$LOCATION_FILE" ]; then
              rm "$LOCATION_FILE"
              echo "✅ Location '$LOCATION_NAME' removed"
            else
              echo "❌ Location '$LOCATION_NAME' not found"
            fi
            ;;
            
          "list")
            echo "📍 Learned Locations:"
            echo "==================="
            
            if [ "$(ls -A "$LOCATIONS_DIR" 2>/dev/null | wc -l)" -eq 0 ]; then
              echo "No locations learned yet."
              echo ""
              echo "Use 'context-learn-location <name>' to learn a new location."
            else
              for location_file in "$LOCATIONS_DIR"/*.json; do
                if [ -f "$location_file" ]; then
                  LOCATION=$(basename "$location_file" .json)
                  WIFI=$(${pkgs.jq}/bin/jq -r '.wifi_ssid' "$location_file" 2>/dev/null || echo "unknown")
                  LAST_SEEN=$(${pkgs.jq}/bin/jq -r '.last_seen' "$location_file" 2>/dev/null || echo "unknown")
                  USAGE=$(${pkgs.jq}/bin/jq -r '.usage_count' "$location_file" 2>/dev/null || echo "0")
                  
                  echo "  📍 $LOCATION"
                  echo "    WiFi: $WIFI"
                  echo "    Last seen: $LAST_SEEN"
                  echo "    Usage count: $USAGE"
                  echo ""
                fi
              done
            fi
            ;;
            
          *)
            echo "Unknown action: $ACTION"
            echo "Use: add, remove, or list"
            ;;
        esac
      '')
      
      # Work pattern analysis
      (writeShellScriptBin "context-analyze-patterns" ''
        #!/bin/bash
        
        # Analyze work patterns from collected context data
        
        set -euo pipefail
        
        ANALYSIS_TYPE="''${1:-summary}"
        DAYS="''${2:-7}"
        
        echo "📊 Work Pattern Analysis"
        echo "======================="
        echo "Analysis type: $ANALYSIS_TYPE"
        echo "Period: Last $DAYS days"
        echo ""
        
        CONTEXT_DIR="$HOME/.local/share/dotfiles-context/environment"
        
        if [ ! -d "$CONTEXT_DIR" ]; then
          echo "❌ No context data found. Run 'context-detect-environment' to start collecting data."
          exit 1
        fi
        
        # Find context files from the last N days
        CUTOFF_DATE=$(date -d "$DAYS days ago" +%s 2>/dev/null || date -j -v-"$DAYS"d +%s 2>/dev/null || echo "0")
        CONTEXT_FILES=$(find "$CONTEXT_DIR" -name "context-*.json" -type f -newer /dev/null 2>/dev/null | head -100)
        
        if [ -z "$CONTEXT_FILES" ]; then
          echo "❌ No recent context data found."
          exit 1
        fi
        
        TOTAL_FILES=$(echo "$CONTEXT_FILES" | wc -l)
        echo "📁 Analyzing $TOTAL_FILES context records..."
        echo ""
        
        case "$ANALYSIS_TYPE" in
          "summary"|"overview")
            echo "🕐 Time Patterns:"
            
            # Time period analysis
            MORNING=0; AFTERNOON=0; EVENING=0; NIGHT=0
            HOME=0; OFFICE=0; PUBLIC=0; UNKNOWN_LOC=0
            CODING=0; MEETING=0; RESEARCH=0; UNKNOWN_SIT=0
            
            while IFS= read -r file; do
              if [ -f "$file" ]; then
                PERIOD=$(${pkgs.jq}/bin/jq -r '.time_context.period // "unknown"' "$file" 2>/dev/null)
                LOCATION=$(${pkgs.jq}/bin/jq -r '.location_context.type // "unknown"' "$file" 2>/dev/null)
                SITUATION=$(${pkgs.jq}/bin/jq -r '.situation_context.primary // "unknown"' "$file" 2>/dev/null)
                
                case "$PERIOD" in
                  "morning") ((MORNING++)) ;;
                  "afternoon") ((AFTERNOON++)) ;;
                  "evening") ((EVENING++)) ;;
                  "night") ((NIGHT++)) ;;
                esac
                
                case "$LOCATION" in
                  "home") ((HOME++)) ;;
                  "office") ((OFFICE++)) ;;
                  "public"|"cafe") ((PUBLIC++)) ;;
                  *) ((UNKNOWN_LOC++)) ;;
                esac
                
                case "$SITUATION" in
                  "coding"|"collaboration") ((CODING++)) ;;
                  "meeting") ((MEETING++)) ;;
                  "research") ((RESEARCH++)) ;;
                  *) ((UNKNOWN_SIT++)) ;;
                esac
              fi
            done <<< "$CONTEXT_FILES"
            
            echo "  🌅 Morning: $MORNING sessions ($(( MORNING * 100 / TOTAL_FILES ))%)"
            echo "  ☀️  Afternoon: $AFTERNOON sessions ($(( AFTERNOON * 100 / TOTAL_FILES ))%)"
            echo "  🌆 Evening: $EVENING sessions ($(( EVENING * 100 / TOTAL_FILES ))%)"
            echo "  🌙 Night: $NIGHT sessions ($(( NIGHT * 100 / TOTAL_FILES ))%)"
            
            echo ""
            echo "📍 Location Patterns:"
            echo "  🏠 Home: $HOME sessions ($(( HOME * 100 / TOTAL_FILES ))%)"
            echo "  🏢 Office: $OFFICE sessions ($(( OFFICE * 100 / TOTAL_FILES ))%)"
            echo "  ☕ Public: $PUBLIC sessions ($(( PUBLIC * 100 / TOTAL_FILES ))%)"
            echo "  ❓ Unknown: $UNKNOWN_LOC sessions ($(( UNKNOWN_LOC * 100 / TOTAL_FILES ))%)"
            
            echo ""
            echo "🎯 Activity Patterns:"
            echo "  💻 Coding: $CODING sessions ($(( CODING * 100 / TOTAL_FILES ))%)"
            echo "  👥 Meetings: $MEETING sessions ($(( MEETING * 100 / TOTAL_FILES ))%)"
            echo "  📚 Research: $RESEARCH sessions ($(( RESEARCH * 100 / TOTAL_FILES ))%)"
            echo "  ❓ Other: $UNKNOWN_SIT sessions ($(( UNKNOWN_SIT * 100 / TOTAL_FILES ))%)"
            ;;
            
          "detailed")
            echo "📈 Detailed Pattern Analysis:"
            echo ""
            
            # Hour-by-hour analysis
            echo "⏰ Activity by Hour:"
            for hour in {00..23}; do
              COUNT=0
              while IFS= read -r file; do
                if [ -f "$file" ]; then
                  FILE_HOUR=$(${pkgs.jq}/bin/jq -r '.detection_time' "$file" 2>/dev/null | cut -d' ' -f2 | cut -d: -f1)
                  if [ "$FILE_HOUR" = "$hour" ]; then
                    ((COUNT++))
                  fi
                fi
              done <<< "$CONTEXT_FILES"
              
              if [ "$COUNT" -gt 0 ]; then
                BARS=$(printf "█%.0s" $(seq 1 $((COUNT * 20 / TOTAL_FILES + 1))))
                echo "  $hour:00 [$BARS] $COUNT sessions"
              fi
            done
            
            echo ""
            echo "📊 Productivity Insights:"
            
            # Find most productive time
            MAX_COUNT=0
            BEST_HOUR=""
            for hour in {00..23}; do
              COUNT=0
              while IFS= read -r file; do
                if [ -f "$file" ]; then
                  FILE_HOUR=$(${pkgs.jq}/bin/jq -r '.detection_time' "$file" 2>/dev/null | cut -d' ' -f2 | cut -d: -f1)
                  ACTIVITY=$(${pkgs.jq}/bin/jq -r '.situation_context.activity_level' "$file" 2>/dev/null)
                  if [ "$FILE_HOUR" = "$hour" ] && [ "$ACTIVITY" = "high" ]; then
                    ((COUNT++))
                  fi
                fi
              done <<< "$CONTEXT_FILES"
              
              if [ "$COUNT" -gt "$MAX_COUNT" ]; then
                MAX_COUNT=$COUNT
                BEST_HOUR=$hour
              fi
            done
            
            if [ -n "$BEST_HOUR" ]; then
              echo "  🎯 Peak productivity: $BEST_HOUR:00 ($MAX_COUNT high-activity sessions)"
            fi
            ;;
            
          "export")
            EXPORT_FILE="$HOME/.local/share/dotfiles-context/pattern-analysis-$(date +%Y%m%d).csv"
            echo "📤 Exporting analysis to: $EXPORT_FILE"
            
            echo "timestamp,time_period,location_type,situation,activity_level,productivity" > "$EXPORT_FILE"
            
            while IFS= read -r file; do
              if [ -f "$file" ]; then
                TIMESTAMP=$(${pkgs.jq}/bin/jq -r '.timestamp' "$file" 2>/dev/null)
                PERIOD=$(${pkgs.jq}/bin/jq -r '.time_context.period' "$file" 2>/dev/null)
                LOCATION=$(${pkgs.jq}/bin/jq -r '.location_context.type' "$file" 2>/dev/null)
                SITUATION=$(${pkgs.jq}/bin/jq -r '.situation_context.primary' "$file" 2>/dev/null)
                ACTIVITY=$(${pkgs.jq}/bin/jq -r '.situation_context.activity_level' "$file" 2>/dev/null)
                PRODUCTIVITY=$(${pkgs.jq}/bin/jq -r '.situation_context.productivity' "$file" 2>/dev/null)
                
                echo "$TIMESTAMP,$PERIOD,$LOCATION,$SITUATION,$ACTIVITY,$PRODUCTIVITY" >> "$EXPORT_FILE"
              fi
            done <<< "$CONTEXT_FILES"
            
            echo "✅ Export completed: $(wc -l < "$EXPORT_FILE") records"
            ;;
            
          *)
            echo "Usage: context-analyze-patterns <type> [days]"
            echo ""
            echo "Types:"
            echo "  summary      - Overview of patterns (default)"
            echo "  detailed     - Detailed hour-by-hour analysis"
            echo "  export       - Export data to CSV"
            echo ""
            echo "Days: Number of days to analyze (default: 7)"
            ;;
        esac
        
        echo ""
        echo "💡 Pattern Analysis Complete"
      '')
    ];
  };
}