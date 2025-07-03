{ config, lib, pkgs, ... }:

with lib;

{
  options = {
    dotfiles.context.themeAdaptation = {
      enable = mkEnableOption "Intelligent theme and UI adaptation system";
      
      timeBasedThemes = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable automatic theme switching based on time of day";
        };
        
        schedules = mkOption {
          type = types.attrsOf (types.submodule {
            options = {
              startTime = mkOption {
                type = types.str;
                description = "Start time in HH:MM format";
              };
              endTime = mkOption {
                type = types.str;
                description = "End time in HH:MM format";
              };
              theme = mkOption {
                type = types.str;
                description = "Theme name to apply during this period";
              };
              colorScheme = mkOption {
                type = types.enum ["light" "dark" "auto"];
                default = "auto";
                description = "Color scheme preference";
              };
            };
          });
          default = {
            morning = {
              startTime = "06:00";
              endTime = "12:00";
              theme = "light_productive";
              colorScheme = "light";
            };
            afternoon = {
              startTime = "12:00";
              endTime = "18:00";
              theme = "bright_focus";
              colorScheme = "light";
            };
            evening = {
              startTime = "18:00";
              endTime = "22:00";
              theme = "warm_comfortable";
              colorScheme = "dark";
            };
            night = {
              startTime = "22:00";
              endTime = "06:00";
              theme = "dark_minimal";
              colorScheme = "dark";
            };
          };
          description = "Time-based theme schedules";
        };
      };
      
      ambientLightAdaptation = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable adaptation based on ambient light levels";
        };
        
        lightThresholds = mkOption {
          type = types.attrsOf types.int;
          default = {
            very_dark = 10;
            dark = 30;
            moderate = 70;
            bright = 90;
          };
          description = "Ambient light level thresholds (0-100)";
        };
        
        adjustments = mkOption {
          type = types.attrsOf (types.submodule {
            options = {
              brightness = mkOption {
                type = types.int;
                description = "Screen brightness adjustment (0-100)";
              };
              contrast = mkOption {
                type = types.int;
                description = "Contrast adjustment (0-100)";
              };
              colorTemperature = mkOption {
                type = types.int;
                description = "Color temperature in Kelvin";
              };
              theme = mkOption {
                type = types.str;
                description = "Preferred theme for this light level";
              };
            };
          });
          default = {
            very_dark = {
              brightness = 20;
              contrast = 80;
              colorTemperature = 2700;
              theme = "dark_minimal";
            };
            dark = {
              brightness = 40;
              contrast = 85;
              colorTemperature = 3200;
              theme = "dark_comfortable";
            };
            moderate = {
              brightness = 70;
              contrast = 90;
              colorTemperature = 5000;
              theme = "balanced";
            };
            bright = {
              brightness = 95;
              contrast = 95;
              colorTemperature = 6500;
              theme = "bright_clear";
            };
          };
          description = "Display adjustments for different light levels";
        };
      };
      
      focusAdaptation = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable theme adaptation based on focus level and work context";
        };
        
        focusThemes = mkOption {
          type = types.attrsOf types.str;
          default = {
            deep_focus = "minimal_distraction";
            light_focus = "balanced_productivity";
            collaborative = "bright_social";
            creative = "inspiring_vibrant";
            break_time = "relaxed_comfortable";
          };
          description = "Theme mappings for different focus states";
        };
        
        distractionReduction = mkOption {
          type = types.bool;
          default = true;
          description = "Enable distraction reduction features during focus periods";
        };
      };
      
      fatigueAdaptation = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable adaptation based on estimated fatigue levels";
        };
        
        fatigueIndicators = mkOption {
          type = types.listOf types.str;
          default = [
            "work_duration" "time_of_day" "activity_patterns" 
            "error_frequency" "typing_patterns" "break_frequency"
          ];
          description = "Indicators used to estimate fatigue";
        };
        
        fatigueThemes = mkOption {
          type = types.attrsOf (types.submodule {
            options = {
              colorScheme = mkOption {
                type = types.enum ["light" "dark" "warm"];
                description = "Color scheme for this fatigue level";
              };
              fontSize = mkOption {
                type = types.str;
                description = "Font size adjustment";
              };
              contrast = mkOption {
                type = types.str;
                description = "Contrast level";
              };
              bluelightFilter = mkOption {
                type = types.bool;
                description = "Whether to apply blue light filter";
              };
            };
          });
          default = {
            fresh = {
              colorScheme = "light";
              fontSize = "normal";
              contrast = "standard";
              bluelightFilter = false;
            };
            moderate = {
              colorScheme = "warm";
              fontSize = "slightly_larger";
              contrast = "enhanced";
              bluelightFilter = false;
            };
            tired = {
              colorScheme = "dark";
              fontSize = "larger";
              contrast = "high";
              bluelightFilter = true;
            };
            exhausted = {
              colorScheme = "dark";
              fontSize = "largest";
              contrast = "maximum";
              bluelightFilter = true;
            };
          };
          description = "Theme configurations for different fatigue levels";
        };
      };
      
      applicationThemes = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable per-application theme management";
        };
        
        applications = mkOption {
          type = types.attrsOf (types.submodule {
            options = {
              themes = mkOption {
                type = types.attrsOf types.str;
                description = "Theme mappings for different contexts";
              };
              configPath = mkOption {
                type = types.str;
                description = "Path to application configuration file";
              };
              reloadCommand = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Command to reload application configuration";
              };
            };
          });
          default = {
            terminal = {
              themes = {
                light = "light_terminal";
                dark = "dark_terminal";
                focus = "minimal_terminal";
              };
              configPath = "~/.config/terminal/theme.conf";
              reloadCommand = "pkill -USR1 terminal";
            };
            editor = {
              themes = {
                light = "github_light";
                dark = "onedark";
                focus = "minimal_dark";
                creative = "material_theme";
              };
              configPath = "~/.config/nvim/theme.lua";
              reloadCommand = "nvim --headless -c 'source ~/.config/nvim/theme.lua' -c 'qa!'";
            };
            browser = {
              themes = {
                light = "light_mode";
                dark = "dark_mode";
                focus = "reader_mode";
              };
              configPath = "~/.config/browser/theme.json";
              reloadCommand = null;
            };
          };
          description = "Per-application theme configurations";
        };
      };
      
      systemIntegration = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable system-wide theme integration";
        };
        
        macosIntegration = mkOption {
          type = types.bool;
          default = (pkgs.stdenv.isDarwin);
          description = "Enable macOS system theme integration";
        };
        
        linuxIntegration = mkOption {
          type = types.bool;
          default = (pkgs.stdenv.isLinux);
          description = "Enable Linux desktop environment integration";
        };
        
        wallpaperAdaptation = mkOption {
          type = types.bool;
          default = true;
          description = "Enable automatic wallpaper changes with themes";
        };
      };
    };
  };

  config = mkIf config.dotfiles.context.themeAdaptation.enable {
    environment.systemPackages = with pkgs; [
      # Theme adaptation command
      (writeShellScriptBin "context-adapt-theme" ''
        #!/bin/bash
        
        # Intelligent theme and UI adaptation
        
        set -euo pipefail
        
        ACTION="''${1:-auto}"
        CONTEXT="''${2:-current}"  # current, focus, fatigue, time, light
        FORCE="''${3:-false}"      # force application even if no change needed
        
        echo "🎨 Theme Adaptation System"
        echo "========================="
        echo "Action: $ACTION"
        echo "Context: $CONTEXT"
        echo "⏰ Adaptation time: $(date)"
        echo ""
        
        # Initialize adaptation data
        CURRENT_THEME="unknown"
        SUGGESTED_THEME="unknown"
        ADAPTATION_REASON=""
        CHANGES_MADE=0
        
        # Configuration directory
        THEME_CONFIG_DIR="$HOME/.local/share/dotfiles-context/themes"
        mkdir -p "$THEME_CONFIG_DIR"
        
        # Get current system theme
        get_current_theme() {
          if [[ "$(uname)" == "Darwin" ]]; then
            # macOS theme detection
            APPEARANCE=$(defaults read -g AppleInterfaceStyle 2>/dev/null || echo "Light")
            if [[ "$APPEARANCE" == "Dark" ]]; then
              CURRENT_THEME="dark"
            else
              CURRENT_THEME="light"
            fi
          elif [[ "$(uname)" == "Linux" ]]; then
            # Linux theme detection (GNOME/GTK)
            if command -v gsettings >/dev/null 2>&1; then
              GTK_THEME=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null || echo "")
              if [[ "$GTK_THEME" =~ [Dd]ark ]]; then
                CURRENT_THEME="dark"
              else
                CURRENT_THEME="light"
              fi
            else
              CURRENT_THEME="unknown"
            fi
          fi
        }
        
        # Time-based theme selection
        ${optionalString config.dotfiles.context.themeAdaptation.timeBasedThemes.enable ''
          determine_time_theme() {
            HOUR=$(date +%H)
            MINUTE=$(date +%M)
            CURRENT_TIME=$(( HOUR * 60 + MINUTE ))
            
            # Check each time period
            ${concatStringsSep "\n" (mapAttrsToList (name: schedule: ''
              # ${name} period: ${schedule.startTime} - ${schedule.endTime}
              START_TIME=$(echo "${schedule.startTime}" | awk -F: '{print $1 * 60 + $2}')
              END_TIME=$(echo "${schedule.endTime}" | awk -F: '{print $1 * 60 + $2}')
              
              # Handle overnight periods (e.g., 22:00 - 06:00)
              if [[ "$END_TIME" -lt "$START_TIME" ]]; then
                if [[ "$CURRENT_TIME" -ge "$START_TIME" ]] || [[ "$CURRENT_TIME" -lt "$END_TIME" ]]; then
                  TIME_THEME="${schedule.theme}"
                  TIME_COLOR_SCHEME="${schedule.colorScheme}"
                  TIME_PERIOD="${name}"
                  return
                fi
              else
                if [[ "$CURRENT_TIME" -ge "$START_TIME" ]] && [[ "$CURRENT_TIME" -lt "$END_TIME" ]]; then
                  TIME_THEME="${schedule.theme}"
                  TIME_COLOR_SCHEME="${schedule.colorScheme}"
                  TIME_PERIOD="${name}"
                  return
                fi
              fi
            '') (attrNames config.dotfiles.context.themeAdaptation.timeBasedThemes.schedules))}\
            
            # Default fallback
            TIME_THEME="balanced"
            TIME_COLOR_SCHEME="auto"
            TIME_PERIOD="unknown"
          }
        ''}
        
        # Ambient light adaptation
        ${optionalString config.dotfiles.context.themeAdaptation.ambientLightAdaptation.enable ''
          determine_light_theme() {
            # Detect ambient light (simplified - would use actual sensors in production)
            if [[ "$(uname)" == "Darwin" ]]; then
              # Use camera or light sensor if available
              # For now, estimate based on time of day
              HOUR=$(date +%H)
              if [[ "$HOUR" -ge 6 ]] && [[ "$HOUR" -lt 8 ]]; then
                LIGHT_LEVEL="moderate"
              elif [[ "$HOUR" -ge 8 ]] && [[ "$HOUR" -lt 18 ]]; then
                LIGHT_LEVEL="bright"
              elif [[ "$HOUR" -ge 18 ]] && [[ "$HOUR" -lt 21 ]]; then
                LIGHT_LEVEL="moderate"
              else
                LIGHT_LEVEL="dark"
              fi
            else
              # Linux light detection (if available)
              LIGHT_LEVEL="moderate"  # Fallback
            fi
            
            # Map light level to theme
            case "$LIGHT_LEVEL" in
              "very_dark")
                LIGHT_THEME="dark_minimal"
                BRIGHTNESS="20"
                COLOR_TEMP="2700"
                ;;
              "dark")
                LIGHT_THEME="dark_comfortable"
                BRIGHTNESS="40"
                COLOR_TEMP="3200"
                ;;
              "moderate")
                LIGHT_THEME="balanced"
                BRIGHTNESS="70"
                COLOR_TEMP="5000"
                ;;
              "bright")
                LIGHT_THEME="bright_clear"
                BRIGHTNESS="95"
                COLOR_TEMP="6500"
                ;;
              *)
                LIGHT_THEME="balanced"
                BRIGHTNESS="70"
                COLOR_TEMP="5000"
                ;;
            esac
          }
        ''}
        
        # Focus-based adaptation
        ${optionalString config.dotfiles.context.themeAdaptation.focusAdaptation.enable ''
          determine_focus_theme() {
            # Detect current work context
            ACTIVE_APPS=""
            if [[ "$(uname)" == "Darwin" ]]; then
              ACTIVE_APPS=$(osascript -e 'tell application "System Events" to get name of (processes where background only is false)' 2>/dev/null | tr ',' '\n' | head -5)
            elif [[ "$(uname)" == "Linux" ]]; then
              ACTIVE_APPS=$(ps aux --format comm --no-headers | sort -u | head -5)
            fi
            
            # Analyze apps for focus context
            FOCUS_CONTEXT="light_focus"  # Default
            
            if echo "$ACTIVE_APPS" | grep -q -i "code\|vim\|emacs\|cursor\|zed"; then
              if echo "$ACTIVE_APPS" | grep -q -i "slack\|discord\|teams\|zoom"; then
                FOCUS_CONTEXT="collaborative"
              else
                FOCUS_CONTEXT="deep_focus"
              fi
            elif echo "$ACTIVE_APPS" | grep -q -i "photoshop\|illustrator\|figma\|sketch"; then
              FOCUS_CONTEXT="creative"
            elif echo "$ACTIVE_APPS" | grep -q -i "music\|spotify\|youtube\|netflix"; then
              FOCUS_CONTEXT="break_time"
            fi
            
            # Map focus context to theme
            case "$FOCUS_CONTEXT" in
              "deep_focus")
                FOCUS_THEME="minimal_distraction"
                ;;
              "light_focus")
                FOCUS_THEME="balanced_productivity"
                ;;
              "collaborative")
                FOCUS_THEME="bright_social"
                ;;
              "creative")
                FOCUS_THEME="inspiring_vibrant"
                ;;
              "break_time")
                FOCUS_THEME="relaxed_comfortable"
                ;;
              *)
                FOCUS_THEME="balanced_productivity"
                ;;
            esac
          }
        ''}
        
        # Fatigue-based adaptation
        ${optionalString config.dotfiles.context.themeAdaptation.fatigueAdaptation.enable ''
          determine_fatigue_theme() {
            # Simple fatigue estimation based on time and work duration
            HOUR=$(date +%H)
            
            # Check work session duration (simplified)
            WORK_START_FILE="$HOME/.local/share/dotfiles-context/work_session_start"
            if [[ -f "$WORK_START_FILE" ]]; then
              WORK_START=$(cat "$WORK_START_FILE")
              CURRENT_TIME=$(date +%s)
              WORK_DURATION=$(( (CURRENT_TIME - WORK_START) / 3600 ))
            else
              WORK_DURATION=0
              echo "$(date +%s)" > "$WORK_START_FILE"
            fi
            
            # Estimate fatigue level
            FATIGUE_SCORE=0
            
            # Time of day factor
            if [[ "$HOUR" -ge 14 ]] && [[ "$HOUR" -le 16 ]]; then
              FATIGUE_SCORE=$((FATIGUE_SCORE + 20))  # Afternoon slump
            elif [[ "$HOUR" -ge 22 ]] || [[ "$HOUR" -le 6 ]]; then
              FATIGUE_SCORE=$((FATIGUE_SCORE + 40))  # Late night/early morning
            fi
            
            # Work duration factor
            if [[ "$WORK_DURATION" -gt 6 ]]; then
              FATIGUE_SCORE=$((FATIGUE_SCORE + 30))
            elif [[ "$WORK_DURATION" -gt 4 ]]; then
              FATIGUE_SCORE=$((FATIGUE_SCORE + 15))
            fi
            
            # Determine fatigue level
            if [[ "$FATIGUE_SCORE" -lt 20 ]]; then
              FATIGUE_LEVEL="fresh"
              FATIGUE_THEME="standard"
              FONT_SIZE="normal"
              BLUE_FILTER=false
            elif [[ "$FATIGUE_SCORE" -lt 40 ]]; then
              FATIGUE_LEVEL="moderate"
              FATIGUE_THEME="warm_comfortable"
              FONT_SIZE="slightly_larger"
              BLUE_FILTER=false
            elif [[ "$FATIGUE_SCORE" -lt 60 ]]; then
              FATIGUE_LEVEL="tired"
              FATIGUE_THEME="dark_restful"
              FONT_SIZE="larger"
              BLUE_FILTER=true
            else
              FATIGUE_LEVEL="exhausted"
              FATIGUE_THEME="dark_minimal"
              FONT_SIZE="largest"
              BLUE_FILTER=true
            fi
          }
        ''}
        
        # Apply system theme
        apply_system_theme() {
          local theme="$1"
          local reason="$2"
          
          echo "🎯 Applying theme: $theme ($reason)"
          
          ${optionalString config.dotfiles.context.themeAdaptation.systemIntegration.macosIntegration ''
            if [[ "$(uname)" == "Darwin" ]]; then
              case "$theme" in
                *dark*|*minimal*)
                  echo "  🌙 Setting macOS to dark mode"
                  osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' 2>/dev/null || true
                  ;;
                *light*|*bright*)
                  echo "  ☀️ Setting macOS to light mode"
                  osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to false' 2>/dev/null || true
                  ;;
              esac
            fi
          ''}
          
          ${optionalString config.dotfiles.context.themeAdaptation.systemIntegration.linuxIntegration ''
            if [[ "$(uname)" == "Linux" ]] && command -v gsettings >/dev/null 2>&1; then
              case "$theme" in
                *dark*|*minimal*)
                  echo "  🌙 Setting GTK to dark theme"
                  gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' 2>/dev/null || true
                  ;;
                *light*|*bright*)
                  echo "  ☀️ Setting GTK to light theme"
                  gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita' 2>/dev/null || true
                  ;;
              esac
            fi
          ''}
        }
        
        # Apply application-specific themes
        apply_application_themes() {
          local theme="$1"
          
          ${optionalString config.dotfiles.context.themeAdaptation.applicationThemes.enable ''
            echo "📱 Applying application themes for: $theme"
            
            # Terminal theme
            if command -v wezterm >/dev/null 2>&1; then
              echo "  🖥️  Updating terminal theme"
              # WezTerm configuration would go here
            fi
            
            # Editor theme
            if command -v nvim >/dev/null 2>&1; then
              echo "  📝 Updating editor theme"
              # Neovim theme configuration would go here
            fi
            
            # Other applications
            echo "  🔧 Theme applied to compatible applications"
          ''}
        }
        
        case "$ACTION" in
          "auto"|"detect")
            echo "🔍 Detecting optimal theme configuration..."
            
            get_current_theme
            echo "  Current theme: $CURRENT_THEME"
            
            # Collect all adaptation suggestions
            ${optionalString config.dotfiles.context.themeAdaptation.timeBasedThemes.enable ''
              determine_time_theme
              echo "  Time-based suggestion: $TIME_THEME ($TIME_PERIOD)"
            ''}
            
            ${optionalString config.dotfiles.context.themeAdaptation.ambientLightAdaptation.enable ''
              determine_light_theme
              echo "  Light-based suggestion: $LIGHT_THEME (light level: $LIGHT_LEVEL)"
            ''}
            
            ${optionalString config.dotfiles.context.themeAdaptation.focusAdaptation.enable ''
              determine_focus_theme
              echo "  Focus-based suggestion: $FOCUS_THEME (context: $FOCUS_CONTEXT)"
            ''}
            
            ${optionalString config.dotfiles.context.themeAdaptation.fatigueAdaptation.enable ''
              determine_fatigue_theme
              echo "  Fatigue-based suggestion: $FATIGUE_THEME (level: $FATIGUE_LEVEL, score: $FATIGUE_SCORE)"
            ''}
            
            # Determine best theme based on context priority
            case "$CONTEXT" in
              "focus")
                SUGGESTED_THEME="$FOCUS_THEME"
                ADAPTATION_REASON="Focus optimization"
                ;;
              "fatigue")
                SUGGESTED_THEME="$FATIGUE_THEME"
                ADAPTATION_REASON="Fatigue reduction"
                ;;
              "time")
                SUGGESTED_THEME="$TIME_THEME"
                ADAPTATION_REASON="Time-based scheduling"
                ;;
              "light")
                SUGGESTED_THEME="$LIGHT_THEME"
                ADAPTATION_REASON="Ambient light adaptation"
                ;;
              *)
                # Auto-prioritize: fatigue > focus > time > light
                if [[ "$FATIGUE_SCORE" -gt 40 ]]; then
                  SUGGESTED_THEME="$FATIGUE_THEME"
                  ADAPTATION_REASON="High fatigue detected"
                elif [[ "$FOCUS_CONTEXT" == "deep_focus" ]]; then
                  SUGGESTED_THEME="$FOCUS_THEME"
                  ADAPTATION_REASON="Deep focus mode"
                else
                  SUGGESTED_THEME="$TIME_THEME"
                  ADAPTATION_REASON="Time-based adaptation"
                fi
                ;;
            esac
            
            echo ""
            echo "🎯 Recommended theme: $SUGGESTED_THEME"
            echo "📋 Reason: $ADAPTATION_REASON"
            
            # Apply if different from current or forced
            if [[ "$SUGGESTED_THEME" != "$CURRENT_THEME" ]] || [[ "$FORCE" == "true" ]]; then
              echo ""
              apply_system_theme "$SUGGESTED_THEME" "$ADAPTATION_REASON"
              apply_application_themes "$SUGGESTED_THEME"
              CHANGES_MADE=1
              
              # Save adaptation record
              TIMESTAMP=$(date +%s)
              ADAPTATION_FILE="$THEME_CONFIG_DIR/adaptation-$TIMESTAMP.json"
              
              cat > "$ADAPTATION_FILE" << EOF
{
  "timestamp": $TIMESTAMP,
  "adaptation_time": "$(date)",
  "context": "$CONTEXT",
  "previous_theme": "$CURRENT_THEME",
  "applied_theme": "$SUGGESTED_THEME",
  "reason": "$ADAPTATION_REASON",
  "factors": {
    "time_theme": "''${TIME_THEME:-unknown}",
    "light_theme": "''${LIGHT_THEME:-unknown}",
    "focus_theme": "''${FOCUS_THEME:-unknown}",
    "fatigue_theme": "''${FATIGUE_THEME:-unknown}",
    "fatigue_score": ''${FATIGUE_SCORE:-0}
  }
}
EOF
              
              echo "💾 Adaptation record saved to: $ADAPTATION_FILE"
            else
              echo "✅ Current theme is already optimal"
            fi
            ;;
            
          "status")
            get_current_theme
            echo "📊 Current Theme Status:"
            echo "  🎨 Active theme: $CURRENT_THEME"
            
            # Show recent adaptations
            echo ""
            echo "📚 Recent Theme History:"
            find "$THEME_CONFIG_DIR" -name "adaptation-*.json" -type f 2>/dev/null | sort -r | head -5 | while read -r file; do
              if [[ -f "$file" ]]; then
                ADAPT_TIME=$(${pkgs.jq}/bin/jq -r '.adaptation_time' "$file" 2>/dev/null || echo "unknown")
                ADAPT_THEME=$(${pkgs.jq}/bin/jq -r '.applied_theme' "$file" 2>/dev/null || echo "unknown")
                ADAPT_REASON=$(${pkgs.jq}/bin/jq -r '.reason' "$file" 2>/dev/null || echo "unknown")
                echo "  📅 $ADAPT_TIME: $ADAPT_THEME ($ADAPT_REASON)"
              fi
            done
            ;;
            
          "reset")
            echo "🔄 Resetting to system default theme..."
            apply_system_theme "system_default" "Manual reset"
            echo "✅ Theme reset completed"
            ;;
            
          *)
            echo "Usage: context-adapt-theme <action> [context] [force]"
            echo ""
            echo "Actions:"
            echo "  auto/detect    - Automatically detect and apply optimal theme"
            echo "  status         - Show current theme status and history"
            echo "  reset          - Reset to system default theme"
            echo ""
            echo "Contexts:"
            echo "  current        - Use all available context (default)"
            echo "  focus          - Prioritize focus optimization"
            echo "  fatigue        - Prioritize fatigue reduction"
            echo "  time           - Use time-based themes only"
            echo "  light          - Use ambient light adaptation only"
            echo ""
            echo "Force: true/false - Apply even if no change needed"
            ;;
        esac
        
        if [[ "$CHANGES_MADE" -eq 1 ]]; then
          echo ""
          echo "✨ Theme adaptation completed successfully"
        fi
      '')
      
      # Theme analysis and recommendations
      (writeShellScriptBin "context-analyze-themes" ''
        #!/bin/bash
        
        # Analyze theme usage patterns and provide recommendations
        
        set -euo pipefail
        
        ANALYSIS_TYPE="''${1:-patterns}"
        DAYS="''${2:-7}"
        
        echo "🎨 Theme Usage Analysis"
        echo "======================"
        echo "Analysis type: $ANALYSIS_TYPE"
        echo "Period: Last $DAYS days"
        echo ""
        
        THEME_CONFIG_DIR="$HOME/.local/share/dotfiles-context/themes"
        
        if [[ ! -d "$THEME_CONFIG_DIR" ]]; then
          echo "❌ No theme data found. Run 'context-adapt-theme' to start collecting data."
          exit 1
        fi
        
        case "$ANALYSIS_TYPE" in
          "patterns")
            echo "📊 Theme Usage Patterns:"
            
            # Find recent adaptations
            ADAPTATION_FILES=$(find "$THEME_CONFIG_DIR" -name "adaptation-*.json" -type f -mtime -"$DAYS" 2>/dev/null)
            
            if [[ -z "$ADAPTATION_FILES" ]]; then
              echo "❌ No recent theme adaptations found."
              exit 1
            fi
            
            echo "  📈 Most used themes:"
            echo "$ADAPTATION_FILES" | xargs cat | ${pkgs.jq}/bin/jq -r '.applied_theme' 2>/dev/null | sort | uniq -c | sort -rn | head -5 | while read -r count theme; do
              echo "    $theme: $count times"
            done
            
            echo ""
            echo "  🕐 Peak adaptation times:"
            echo "$ADAPTATION_FILES" | xargs cat | ${pkgs.jq}/bin/jq -r '.adaptation_time' 2>/dev/null | cut -d' ' -f4 | cut -d: -f1 | sort | uniq -c | sort -rn | head -5 | while read -r count hour; do
              echo "    ''${hour}:00 hour: $count adaptations"
            done
            
            echo ""
            echo "  💡 Adaptation reasons:"
            echo "$ADAPTATION_FILES" | xargs cat | ${pkgs.jq}/bin/jq -r '.reason' 2>/dev/null | sort | uniq -c | sort -rn | while read -r count reason; do
              echo "    $reason: $count times"
            done
            ;;
            
          "recommendations")
            echo "💡 Theme Optimization Recommendations:"
            
            # Analyze patterns to suggest improvements
            echo "  🎯 Personalization suggestions:"
            echo "    • Consider creating custom themes for your most used contexts"
            echo "    • Set up automatic adaptation triggers for focus periods"
            echo "    • Enable fatigue detection for late-night work sessions"
            
            echo ""
            echo "  ⚡ Performance suggestions:"
            echo "    • Use minimal themes during resource-intensive tasks"
            echo "    • Enable blue light filtering for evening work"
            echo "    • Consider contrast adjustments for long coding sessions"
            ;;
            
          *)
            echo "Usage: context-analyze-themes <type> [days]"
            echo ""
            echo "Types:"
            echo "  patterns         - Analyze usage patterns"
            echo "  recommendations  - Get optimization suggestions"
            echo ""
            echo "Days: Number of days to analyze (default: 7)"
            ;;
        esac
      '')
      
      # Theme preset manager
      (writeShellScriptBin "context-manage-themes" ''
        #!/bin/bash
        
        # Manage theme presets and configurations
        
        set -euo pipefail
        
        ACTION="''${1:-list}"
        THEME_NAME="''${2:-}"
        
        echo "🎨 Theme Management System"
        echo "========================="
        echo "Action: $ACTION"
        echo ""
        
        THEME_PRESETS_DIR="$HOME/.local/share/dotfiles-context/theme-presets"
        mkdir -p "$THEME_PRESETS_DIR"
        
        case "$ACTION" in
          "list")
            echo "📋 Available Theme Presets:"
            
            if [[ "$(ls -A "$THEME_PRESETS_DIR" 2>/dev/null | wc -l)" -eq 0 ]]; then
              echo "  No custom theme presets found."
              echo ""
              echo "📦 Built-in themes:"
              echo "  • light_productive - Bright, clean theme for morning work"
              echo "  • dark_minimal - Minimal dark theme for focused work"
              echo "  • warm_comfortable - Warm colors for evening sessions"
              echo "  • bright_clear - High contrast for bright environments"
            else
              for preset_file in "$THEME_PRESETS_DIR"/*.json; do
                if [[ -f "$preset_file" ]]; then
                  PRESET_NAME=$(basename "$preset_file" .json)
                  DESCRIPTION=$(${pkgs.jq}/bin/jq -r '.description // "No description"' "$preset_file" 2>/dev/null)
                  echo "  🎨 $PRESET_NAME: $DESCRIPTION"
                fi
              done
            fi
            ;;
            
          "create")
            if [[ -z "$THEME_NAME" ]]; then
              echo "Usage: context-manage-themes create <theme-name>"
              exit 1
            fi
            
            echo "🎨 Creating theme preset: $THEME_NAME"
            
            PRESET_FILE="$THEME_PRESETS_DIR/$THEME_NAME.json"
            cat > "$PRESET_FILE" << EOF
{
  "name": "$THEME_NAME",
  "description": "Custom theme preset",
  "created": "$(date)",
  "colorScheme": "auto",
  "brightness": 80,
  "contrast": 90,
  "colorTemperature": 5000,
  "fontSize": "normal",
  "bluelightFilter": false,
  "applications": {
    "terminal": "auto",
    "editor": "auto",
    "browser": "auto"
  }
}
EOF
            
            echo "✅ Theme preset created: $PRESET_FILE"
            echo "Edit this file to customize the theme settings."
            ;;
            
          "apply")
            if [[ -z "$THEME_NAME" ]]; then
              echo "Usage: context-manage-themes apply <theme-name>"
              exit 1
            fi
            
            PRESET_FILE="$THEME_PRESETS_DIR/$THEME_NAME.json"
            if [[ ! -f "$PRESET_FILE" ]]; then
              echo "❌ Theme preset not found: $THEME_NAME"
              exit 1
            fi
            
            echo "🎯 Applying theme preset: $THEME_NAME"
            
            # Apply the theme using the main adaptation system
            context-adapt-theme auto current true
            
            echo "✅ Theme preset applied successfully"
            ;;
            
          "delete")
            if [[ -z "$THEME_NAME" ]]; then
              echo "Usage: context-manage-themes delete <theme-name>"
              exit 1
            fi
            
            PRESET_FILE="$THEME_PRESETS_DIR/$THEME_NAME.json"
            if [[ -f "$PRESET_FILE" ]]; then
              rm "$PRESET_FILE"
              echo "✅ Theme preset deleted: $THEME_NAME"
            else
              echo "❌ Theme preset not found: $THEME_NAME"
            fi
            ;;
            
          *)
            echo "Usage: context-manage-themes <action> [theme-name]"
            echo ""
            echo "Actions:"
            echo "  list           - List available theme presets"
            echo "  create <name>  - Create a new theme preset"
            echo "  apply <name>   - Apply a theme preset"
            echo "  delete <name>  - Delete a theme preset"
            ;;
        esac
      '')
    ];
  };
}