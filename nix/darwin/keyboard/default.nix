# QMK/VIA Custom Keyboard Integration
# Advanced keyboard configuration with QMK firmware and VIA support
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.keyboard;
  
  # QMK keyboard definitions
  supportedKeyboards = {
    "planck" = {
      name = "Planck";
      layout = "planck";
      firmware = "planck_rev6_default.hex";
      features = [ "audio" "rgb_matrix" "rotary_encoder" ];
    };
    "preonic" = {
      name = "Preonic";
      layout = "preonic";
      firmware = "preonic_rev3_default.hex";
      features = [ "audio" "rgb_matrix" ];
    };
    "ergodox_ez" = {
      name = "ErgoDox EZ";
      layout = "ergodox_ez";
      firmware = "ergodox_ez_default.hex";
      features = [ "rgb_matrix" "oryx" ];
    };
    "moonlander" = {
      name = "Moonlander";
      layout = "moonlander";
      firmware = "moonlander_default.hex";
      features = [ "rgb_matrix" "oryx" "rotary_encoder" ];
    };
    "corne" = {
      name = "Corne (CRKBD)";
      layout = "corne";
      firmware = "crkbd_default.hex";
      features = [ "split" "oled" "rgb_matrix" ];
    };
    "lily58" = {
      name = "Lily58";
      layout = "lily58";
      firmware = "lily58_default.hex";
      features = [ "split" "oled" "rotary_encoder" ];
    };
    "kyria" = {
      name = "Kyria";
      layout = "kyria";
      firmware = "kyria_default.hex";
      features = [ "split" "oled" "rgb_matrix" "rotary_encoder" ];
    };
  };
in
{
  options.dotfiles.keyboard = {
    enable = mkEnableOption "QMK/VIA custom keyboard integration";
    
    qmk = {
      enable = mkEnableOption "QMK firmware support" // { default = true; };
      
      keyboards = mkOption {
        type = types.listOf (types.enum (attrNames supportedKeyboards));
        default = [];
        description = "List of QMK keyboards to support";
        example = [ "planck" "corne" ];
      };
      
      customFirmware = mkOption {
        type = types.bool;
        default = false;
        description = "Enable custom firmware compilation";
      };
      
      autoFlash = mkOption {
        type = types.bool;
        default = false;
        description = "Enable automatic firmware flashing";
      };
    };
    
    via = {
      enable = mkEnableOption "VIA keyboard configuration tool" // { default = true; };
      
      autoDetect = mkOption {
        type = types.bool;
        default = true;
        description = "Automatically detect VIA-compatible keyboards";
      };
      
      layouts = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Custom keyboard layout files";
      };
    };
    
    keymaps = {
      enable = mkEnableOption "Custom keymap management";
      
      profile = mkOption {
        type = types.enum [ "developer" "writer" "gamer" "minimal" "custom" ];
        default = "developer";
        description = "Keymap profile for different use cases";
      };
      
      layers = mkOption {
        type = types.int;
        default = 4;
        description = "Number of keymap layers";
      };
      
      macros = mkEnableOption "Enable macro support";
      tapDance = mkEnableOption "Enable tap dance features";
      combos = mkEnableOption "Enable key combinations";
    };
    
    features = {
      rgbLighting = mkEnableOption "RGB lighting support";
      audio = mkEnableOption "Audio feedback support";
      oled = mkEnableOption "OLED display support";
      rotaryEncoder = mkEnableOption "Rotary encoder support";
      hapticFeedback = mkEnableOption "Haptic feedback support";
      
      aiIntegration = mkOption {
        type = types.bool;
        default = false;
        description = "Enable AI-powered keymap optimization";
      };
    };
    
    development = {
      enable = mkEnableOption "Keyboard development environment";
      
      compiler = mkOption {
        type = types.enum [ "avr-gcc" "arm-gcc" "clang" ];
        default = "avr-gcc";
        description = "Compiler for QMK firmware";
      };
      
      debugger = mkEnableOption "Enable debugging tools";
      simulator = mkEnableOption "Enable keyboard simulator";
    };
  };

  config = mkIf cfg.enable {
    # Core QMK/VIA packages
    home-manager.users.yuki.home.packages = with pkgs; 
      # Base packages
      [
        # QMK toolchain (if available in nixpkgs)
        # Note: QMK CLI might need to be installed via pip/homebrew
        git
        curl
        wget
        unzip
      ] ++
      
      # QMK development tools
      (optionals cfg.qmk.enable [
        # QMK dependencies
        python3
        python3Packages.pip
        python3Packages.setuptools
        dfu-util
        dfu-programmer
        avrdude
        
        # ARM development tools
        gcc-arm-embedded
        
        # AVR development tools (if available)
        # avr-gcc # Not available on macOS ARM64
        # avr-libc
        # avr-binutils
      ]) ++
      
      # Development tools
      (optionals cfg.development.enable [
        gnumake
        cmake
        ninja
        
        # Debugging tools
        (mkIf cfg.development.debugger gdb)
        
        # Additional development utilities
        hexdump
        minicom  # Serial communication
      ]);
    
    # VIA application installation via Homebrew (better macOS integration)
    # Note: VIA is not available in nixpkgs for macOS
    homebrew.casks = mkIf cfg.via.enable [
      "via"
    ];
    
    # QMK CLI installation script
    home-manager.users.yuki.home.file."bin/qmk-setup" = mkIf cfg.qmk.enable {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # QMK Development Environment Setup
        set -euo pipefail
        
        echo "🛠️  Setting up QMK Development Environment"
        echo "========================================="
        
        # Install QMK CLI
        if ! command -v qmk &> /dev/null; then
          echo "📦 Installing QMK CLI..."
          
          if command -v pip3 &> /dev/null; then
            pip3 install --user qmk
            echo "✅ QMK CLI installed via pip"
          else
            echo "❌ pip3 not found. Installing via Homebrew..."
            if command -v brew &> /dev/null; then
              brew install qmk/qmk/qmk
              echo "✅ QMK CLI installed via Homebrew"
            else
              echo "❌ Neither pip nor Homebrew available"
              exit 1
            fi
          fi
        else
          echo "✅ QMK CLI already installed: $(qmk --version)"
        fi
        
        # Setup QMK environment
        echo "🔧 Setting up QMK environment..."
        
        # Create QMK directory
        QMK_HOME="$HOME/qmk_firmware"
        if [[ ! -d "$QMK_HOME" ]]; then
          echo "📂 Cloning QMK firmware repository..."
          git clone --recurse-submodules https://github.com/qmk/qmk_firmware.git "$QMK_HOME"
        else
          echo "✅ QMK firmware directory exists"
        fi
        
        # Setup QMK
        cd "$QMK_HOME"
        echo "⚙️  Running QMK setup..."
        qmk setup -y
        
        # Install supported keyboards
        ${concatStringsSep "\n" (map (kb: ''
          echo "🔧 Setting up ${supportedKeyboards.${kb}.name}..."
          qmk compile -kb ${supportedKeyboards.${kb}.layout} -km default
        '') cfg.qmk.keyboards)}
        
        echo ""
        echo "🎉 QMK setup complete!"
        echo ""
        echo "📋 Available Commands:"
        echo "  qmk list-keyboards    - List available keyboards"
        echo "  qmk compile          - Compile firmware"
        echo "  qmk flash           - Flash firmware to keyboard"
        echo "  qmk-keymap-manager   - Manage custom keymaps"
        echo ""
        echo "📁 QMK Home: $QMK_HOME"
      '';
    };
    
    # Custom keymap management
    home-manager.users.yuki.home.file."bin/qmk-keymap-manager" = mkIf cfg.keymaps.enable {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # QMK Keymap Management Tool
        set -euo pipefail
        
        ACTION="''${1:-list}"
        KEYBOARD="''${2:-}"
        KEYMAP="''${3:-}"
        
        QMK_HOME="$HOME/qmk_firmware"
        KEYMAP_DIR="$HOME/.config/qmk/keymaps"
        
        echo "🔤 QMK Keymap Manager"
        echo "===================="
        
        # Ensure directories exist
        mkdir -p "$KEYMAP_DIR"
        
        case "$ACTION" in
          "list")
            echo "📋 Available Keyboards:"
            ${concatStringsSep "\n" (map (kb: ''
              echo "  📺 ${supportedKeyboards.${kb}.name} (${kb})"
              echo "     Features: ${concatStringsSep ", " supportedKeyboards.${kb}.features}"
            '') cfg.qmk.keyboards)}
            
            echo ""
            echo "🗂️  Custom Keymaps:"
            if [[ -d "$KEYMAP_DIR" ]]; then
              find "$KEYMAP_DIR" -name "*.json" -exec basename {} .json \; | sort
            else
              echo "  No custom keymaps found"
            fi
            ;;
            
          "create")
            if [[ -z "$KEYBOARD" || -z "$KEYMAP" ]]; then
              echo "Usage: qmk-keymap-manager create <keyboard> <keymap_name>"
              echo "Example: qmk-keymap-manager create planck my_layout"
              exit 1
            fi
            
            echo "🎨 Creating keymap '$KEYMAP' for $KEYBOARD..."
            
            # Generate base keymap based on profile
            PROFILE="${cfg.keymaps.profile}"
            KEYMAP_FILE="$KEYMAP_DIR/$KEYBOARD-$KEYMAP.json"
            
            # Create keymap template
            cat > "$KEYMAP_FILE" << EOF
        {
          "version": 1,
          "notes": "Custom keymap for $KEYBOARD - Profile: $PROFILE",
          "keyboard": "$KEYBOARD",
          "keymap": "$KEYMAP",
          "layout": "LAYOUT",
          "layers": [
            $(case "$PROFILE" in
              "developer")
                echo '"Developer-optimized layer with programming symbols"'
                ;;
              "writer")
                echo '"Writer-optimized layer with text editing shortcuts"'
                ;;
              "gamer")
                echo '"Gaming-optimized layer with macro keys"'
                ;;
              "minimal")
                echo '"Minimal layer with essential keys only"'
                ;;
              *)
                echo '"Custom layer configuration"'
                ;;
            esac)
          ]
        }
        EOF
            
            echo "✅ Keymap template created: $KEYMAP_FILE"
            echo "💡 Edit with VIA or your preferred JSON editor"
            ;;
            
          "compile")
            if [[ -z "$KEYBOARD" || -z "$KEYMAP" ]]; then
              echo "Usage: qmk-keymap-manager compile <keyboard> <keymap_name>"
              exit 1
            fi
            
            KEYMAP_FILE="$KEYMAP_DIR/$KEYBOARD-$KEYMAP.json"
            
            if [[ ! -f "$KEYMAP_FILE" ]]; then
              echo "❌ Keymap file not found: $KEYMAP_FILE"
              exit 1
            fi
            
            echo "🔨 Compiling keymap '$KEYMAP' for $KEYBOARD..."
            
            cd "$QMK_HOME"
            qmk compile "$KEYMAP_FILE"
            
            echo "✅ Compilation complete!"
            ;;
            
          "flash")
            if [[ -z "$KEYBOARD" || -z "$KEYMAP" ]]; then
              echo "Usage: qmk-keymap-manager flash <keyboard> <keymap_name>"
              exit 1
            fi
            
            KEYMAP_FILE="$KEYMAP_DIR/$KEYBOARD-$KEYMAP.json"
            
            if [[ ! -f "$KEYMAP_FILE" ]]; then
              echo "❌ Keymap file not found: $KEYMAP_FILE"
              exit 1
            fi
            
            echo "⚡ Flashing keymap '$KEYMAP' to $KEYBOARD..."
            echo "🔌 Put your keyboard in bootloader mode now..."
            
            cd "$QMK_HOME"
            qmk flash "$KEYMAP_FILE"
            
            echo "✅ Flashing complete!"
            ;;
            
          "backup")
            echo "💾 Backing up keymaps..."
            
            BACKUP_DIR="$HOME/.config/qmk/backups/$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$BACKUP_DIR"
            
            if [[ -d "$KEYMAP_DIR" ]]; then
              cp -r "$KEYMAP_DIR"/* "$BACKUP_DIR/"
              echo "✅ Keymaps backed up to: $BACKUP_DIR"
            else
              echo "⚠️  No keymaps to backup"
            fi
            ;;
            
          *)
            echo "Usage: qmk-keymap-manager <action> [keyboard] [keymap]"
            echo ""
            echo "Actions:"
            echo "  list              - List available keyboards and keymaps"
            echo "  create <kb> <km>  - Create new keymap template"
            echo "  compile <kb> <km> - Compile keymap"
            echo "  flash <kb> <km>   - Flash keymap to keyboard"
            echo "  backup            - Backup all keymaps"
            echo ""
            echo "Supported Keyboards: ${concatStringsSep ", " cfg.qmk.keyboards}"
            ;;
        esac
      '';
    };
    
    # VIA configuration and layouts
    home-manager.users.yuki.home.file.".config/via" = mkIf cfg.via.enable {
      recursive = true;
      source = ./via-config;
    };
    
    # AI-powered keymap optimization
    home-manager.users.yuki.home.file."bin/qmk-ai-optimizer" = mkIf cfg.features.aiIntegration {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # AI-Powered Keymap Optimization
        set -euo pipefail
        
        echo "🤖 QMK AI Keymap Optimizer"
        echo "=========================="
        
        # Check if Ollama is available
        if ! command -v ollama-manager &> /dev/null; then
          echo "❌ Ollama Manager not found"
          echo "💡 Install with: ollama-manager setup"
          exit 1
        fi
        
        if ! ollama-manager status | grep -q "Service: Running"; then
          echo "❌ Ollama service not running"
          echo "💡 Start with: ollama-manager start"
          exit 1
        fi
        
        KEYBOARD="''${1:-}"
        USAGE_PROFILE="''${2:-${cfg.keymaps.profile}}"
        
        if [[ -z "$KEYBOARD" ]]; then
          echo "Usage: qmk-ai-optimizer <keyboard> [usage_profile]"
          echo "Available keyboards: ${concatStringsSep ", " cfg.qmk.keyboards}"
          echo "Usage profiles: developer, writer, gamer, minimal"
          exit 1
        fi
        
        echo "🔍 Analyzing keymap optimization for $KEYBOARD..."
        echo "📊 Usage profile: $USAGE_PROFILE"
        
        # Gather system context
        CURRENT_LAYOUT=$(setxkbmap -query 2>/dev/null | grep layout | awk '{print $2}' || echo "unknown")
        TYPING_SPEED=$(defaults read -g InitialKeyRepeat 2>/dev/null || echo "unknown")
        
        # Create optimization context
        CONTEXT="Keyboard: $KEYBOARD, Profile: $USAGE_PROFILE, Current layout: $CURRENT_LAYOUT, Typing speed: $TYPING_SPEED"
        
        echo "🧠 Generating AI optimization recommendations..."
        
        AI_PROMPT="Optimize QMK keymap for: $CONTEXT. Provide specific recommendations for:
        1. Layer organization (max ${toString cfg.keymaps.layers} layers)
        2. Key placement optimization
        3. Macro suggestions for $USAGE_PROFILE use
        4. Tap dance and combo opportunities
        5. RGB lighting patterns
        
        Focus on ergonomics and efficiency. Provide actionable recommendations."
        
        AI_RESPONSE=$(echo "$AI_PROMPT" | ollama-manager chat codellama)
        
        echo ""
        echo "🎯 AI Optimization Recommendations:"
        echo "=================================="
        echo "$AI_RESPONSE"
        
        # Save recommendations
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        RECOMMENDATIONS_FILE="$HOME/.config/qmk/ai-recommendations/$KEYBOARD-$TIMESTAMP.md"
        mkdir -p "$(dirname "$RECOMMENDATIONS_FILE")"
        
        cat > "$RECOMMENDATIONS_FILE" << EOF
        # QMK AI Optimization Recommendations
        
        **Keyboard:** $KEYBOARD  
        **Profile:** $USAGE_PROFILE  
        **Generated:** $(date)  
        **Context:** $CONTEXT
        
        ## Recommendations
        
        $AI_RESPONSE
        
        ## Implementation Notes
        
        - Use VIA for real-time keymap adjustments
        - Test changes incrementally
        - Backup current keymap before applying changes
        - Monitor usage patterns for further optimization
        
        Generated by QMK AI Optimizer
        EOF
        
        echo ""
        echo "💾 Recommendations saved to: $RECOMMENDATIONS_FILE"
        echo "🔧 Use 'qmk-keymap-manager create $KEYBOARD ai-optimized' to create optimized keymap"
      '';
    };
    
    # Keyboard health and usage monitoring
    home-manager.users.yuki.home.file."bin/qmk-health-monitor" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # QMK/VIA Health and Usage Monitor
        set -euo pipefail
        
        echo "🩺 QMK/VIA Health Monitor"
        echo "========================"
        
        # Check QMK installation
        echo "🔧 QMK Installation:"
        if command -v qmk &> /dev/null; then
          echo "  ✅ QMK CLI: $(qmk --version)"
          
          QMK_HOME="$HOME/qmk_firmware"
          if [[ -d "$QMK_HOME" ]]; then
            echo "  ✅ QMK Firmware: Available"
            cd "$QMK_HOME"
            LAST_UPDATE=$(git log -1 --format=%cd --date=short)
            echo "  📅 Last Update: $LAST_UPDATE"
          else
            echo "  ❌ QMK Firmware: Not found"
            echo "  💡 Run: qmk-setup"
          fi
        else
          echo "  ❌ QMK CLI: Not installed"
          echo "  💡 Run: qmk-setup"
        fi
        
        # Check VIA
        echo ""
        echo "🎛️  VIA Application:"
        ${if cfg.via.enable then ''
          if [[ -d "/Applications/VIA.app" ]]; then
            echo "  ✅ VIA: Installed"
          else
            echo "  ❌ VIA: Not found"
            echo "  💡 Install with: brew install --cask via"
          fi
        '' else ''
          echo "  ⚪ VIA: Disabled in configuration"
        ''}
        
        # Check connected keyboards
        echo ""
        echo "⌨️  Connected Keyboards:"
        
        # Use ioreg to detect USB keyboards (macOS)
        KEYBOARDS=$(ioreg -p IOUSB -w0 | grep -i keyboard | wc -l)
        echo "  📊 Total keyboards detected: $KEYBOARDS"
        
        # List specific keyboard info
        ioreg -p IOUSB -w0 | grep -i keyboard -A 5 -B 5 | grep -E "(class|Product|Vendor)" | head -10
        
        # Check for QMK keyboards (look for VIA-compatible devices)
        echo ""
        echo "🔍 QMK/VIA Compatible Devices:"
        
        # Check USB devices that might be QMK keyboards
        QMK_DEVICES=$(ioreg -p IOUSB -w0 | grep -i -E "(planck|preonic|ergodox|moonlander|corne|lily58|kyria)" | wc -l)
        
        if [[ $QMK_DEVICES -gt 0 ]]; then
          echo "  ✅ QMK devices detected: $QMK_DEVICES"
          ioreg -p IOUSB -w0 | grep -i -E "(planck|preonic|ergodox|moonlander|corne|lily58|kyria)" -A 2
        else
          echo "  ⚪ No known QMK devices detected"
          echo "  💡 Devices may be in normal (non-bootloader) mode"
        fi
        
        # Check keymap configurations
        echo ""
        echo "🗂️  Keymap Configurations:"
        
        KEYMAP_DIR="$HOME/.config/qmk/keymaps"
        if [[ -d "$KEYMAP_DIR" ]]; then
          KEYMAP_COUNT=$(find "$KEYMAP_DIR" -name "*.json" | wc -l)
          echo "  📁 Custom keymaps: $KEYMAP_COUNT"
          
          if [[ $KEYMAP_COUNT -gt 0 ]]; then
            echo "  📋 Available keymaps:"
            find "$KEYMAP_DIR" -name "*.json" -exec basename {} .json \; | sort | sed 's/^/    /'
          fi
        else
          echo "  ⚪ No custom keymaps directory found"
        fi
        
        # Check AI integration
        ${if cfg.features.aiIntegration then ''
          echo ""
          echo "🤖 AI Integration:"
          if command -v ollama-manager &> /dev/null; then
            echo "  ✅ Ollama Manager: Available"
            if ollama-manager status | grep -q "Service: Running"; then
              echo "  ✅ AI Service: Running"
              
              # Check AI recommendations
              AI_RECS_DIR="$HOME/.config/qmk/ai-recommendations"
              if [[ -d "$AI_RECS_DIR" ]]; then
                REC_COUNT=$(find "$AI_RECS_DIR" -name "*.md" | wc -l)
                echo "  📊 AI Recommendations: $REC_COUNT generated"
              fi
            else
              echo "  ⚠️  AI Service: Not running"
            fi
          else
            echo "  ❌ Ollama Manager: Not available"
          fi
        '' else ''
          echo ""
          echo "🤖 AI Integration: Disabled in configuration"
        ''}
        
        # System keyboard settings
        echo ""
        echo "⚙️  System Keyboard Settings:"
        echo "  🔁 Key Repeat Rate: $(defaults read -g KeyRepeat 2>/dev/null || echo "unknown")"
        echo "  ⏱️  Initial Key Repeat: $(defaults read -g InitialKeyRepeat 2>/dev/null || echo "unknown")"
        echo "  🔄 Caps Lock Mapping: $(defaults read -g com.apple.keyboard.modifiermapping.1452-610-0 2>/dev/null | grep -o "Caps Lock" || echo "default")"
        
        # Usage statistics
        echo ""
        echo "📊 Usage Statistics:"
        
        # Check if we have typing statistics
        STATS_FILE="$HOME/.config/qmk/usage-stats.log"
        if [[ -f "$STATS_FILE" ]]; then
          TOTAL_SESSIONS=$(wc -l < "$STATS_FILE")
          echo "  📈 Recorded sessions: $TOTAL_SESSIONS"
          
          if [[ $TOTAL_SESSIONS -gt 0 ]]; then
            LAST_SESSION=$(tail -1 "$STATS_FILE")
            echo "  🕐 Last session: $LAST_SESSION"
          fi
        else
          echo "  ⚪ No usage statistics available"
          echo "  💡 Enable usage tracking in QMK configuration"
        fi
        
        echo ""
        echo "🎯 Summary:"
        echo "  ⌨️  QMK Support: ${if cfg.qmk.enable then "Enabled" else "Disabled"}"
        echo "  🎛️  VIA Support: ${if cfg.via.enable then "Enabled" else "Disabled"}"
        echo "  🗂️  Keymap Management: ${if cfg.keymaps.enable then "Enabled" else "Disabled"}"
        echo "  🤖 AI Integration: ${if cfg.features.aiIntegration then "Enabled" else "Disabled"}"
        echo "  🛠️  Development Mode: ${if cfg.development.enable then "Enabled" else "Disabled"}"
        
        echo ""
        echo "🔧 Available Commands:"
        echo "  qmk-setup              - Set up QMK development environment"
        echo "  qmk-keymap-manager     - Manage custom keymaps"
        ${if cfg.features.aiIntegration then ''
          echo "  qmk-ai-optimizer       - Generate AI-powered optimizations"
        '' else ""}
        echo "  qmk-health-monitor     - This health check tool"
      '';
    };
    
    # Shell aliases for QMK/VIA management
    home-manager.users.yuki.programs.zsh.shellAliases = {
      # QMK shortcuts
      qmk-setup = "qmk-setup";
      qmk-health = "qmk-health-monitor";
      qmk-keymap = "qmk-keymap-manager";
      qmk-compile = "qmk compile";
      qmk-flash = "qmk flash";
      
      # VIA shortcuts
      via-open = mkIf cfg.via.enable "open -a VIA";
      
      # AI optimization
      qmk-ai = mkIf cfg.features.aiIntegration "qmk-ai-optimizer";
      
      # Development shortcuts
      qmk-dev = mkIf cfg.development.enable "cd $HOME/qmk_firmware";
    };
    
    # Environment variables
    home-manager.users.yuki.home.sessionVariables = {
      QMK_HOME = "$HOME/qmk_firmware";
      QMK_CONFIG_HOME = "$HOME/.config/qmk";
    } // (optionalAttrs cfg.development.enable {
      QMK_DEVELOPER_MODE = "1";
    });
    
    # Zsh completion and integration
    home-manager.users.yuki.programs.zsh.initContent = mkIf cfg.qmk.enable ''
      # QMK completion
      if command -v qmk &> /dev/null; then
        eval "$(qmk generate-completion zsh)"
      fi
      
      # QMK helper functions
      qmk-quick-compile() {
        local keyboard="''${1:-}"
        local keymap="''${2:-default}"
        
        if [[ -z "$keyboard" ]]; then
          echo "Usage: qmk-quick-compile <keyboard> [keymap]"
          echo "Example: qmk-quick-compile planck my_layout"
          return 1
        fi
        
        echo "🔨 Quick compiling $keyboard:$keymap..."
        qmk compile -kb "$keyboard" -km "$keymap"
      }
      
      qmk-quick-flash() {
        local keyboard="''${1:-}"
        local keymap="''${2:-default}"
        
        if [[ -z "$keyboard" ]]; then
          echo "Usage: qmk-quick-flash <keyboard> [keymap]"
          echo "Example: qmk-quick-flash planck my_layout"
          return 1
        fi
        
        echo "⚡ Quick flashing $keyboard:$keymap..."
        echo "🔌 Put your keyboard in bootloader mode now..."
        qmk flash -kb "$keyboard" -km "$keymap"
      }
    '';
  };
}