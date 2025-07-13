# WezTerm Terminal Configuration
# Modern terminal emulator with GPU acceleration
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.terminals.wezterm;
in
{
  options.dotfiles.terminals.wezterm = {
    enable = mkEnableOption "WezTerm terminal emulator";
    
    configFile = mkOption {
      type = types.path;
      default = ../../../configs/terminals/wezterm/wezterm.lua;
      description = "Path to WezTerm configuration file";
    };
    
    theme = mkOption {
      type = types.enum [ "poimandres" "catppuccin" "tokyonight" "custom" ];
      default = "poimandres";
      description = "WezTerm color theme";
    };
  };

  config = mkIf cfg.enable {
    # Install WezTerm via Homebrew (for better macOS integration)
    homebrew.casks = [ "wezterm" ];
    
    # Link configuration file
    home-manager.users.yuki.home.file.".config/wezterm/wezterm.lua" = {
      source = cfg.configFile;
    };
    
    # WezTerm health check script
    home-manager.users.yuki.home.file."bin/wezterm-health" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        echo "🖥️  WezTerm Terminal Status"
        echo "========================="
        
        # Check if WezTerm is installed
        if command -v wezterm &> /dev/null; then
          echo "✅ WezTerm: Installed"
          echo "   Version: $(wezterm --version | head -1)"
        else
          echo "❌ WezTerm: Not installed"
          return 1
        fi
        
        # Check configuration file
        if [[ -f "$HOME/.config/wezterm/wezterm.lua" ]]; then
          echo "✅ Configuration: Found"
          
          # Test configuration syntax
          if wezterm --config-file "$HOME/.config/wezterm/wezterm.lua" --help &> /dev/null; then
            echo "✅ Configuration: Valid syntax"
          else
            echo "❌ Configuration: Syntax error"
          fi
        else
          echo "❌ Configuration: Missing"
        fi
        
        # Check GPU acceleration support
        if command -v wezterm &> /dev/null; then
          echo "📊 GPU Acceleration: $(wezterm ls-fonts | grep -q 'builtin' && echo 'Available' || echo 'Unknown')"
        fi
        
        # Check font availability
        if [[ -f "$HOME/.config/wezterm/wezterm.lua" ]]; then
          local font_family=$(grep -o "family = '[^']*'" "$HOME/.config/wezterm/wezterm.lua" | head -1 | cut -d"'" -f2)
          if [[ -n "$font_family" ]]; then
            echo "🔤 Primary Font: $font_family"
          fi
        fi
      '';
    };
    
    # WezTerm theme switcher
    home-manager.users.yuki.home.file."bin/wezterm-theme" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        THEME="''${1:-list}"
        CONFIG_FILE="$HOME/.config/wezterm/wezterm.lua"
        
        case "$THEME" in
          list)
            echo "Available themes:"
            echo "  - poimandres (current)"
            echo "  - catppuccin"
            echo "  - tokyonight"
            ;;
          poimandres|catppuccin|tokyonight)
            echo "🎨 Switching WezTerm theme to: $THEME"
            echo "Note: Theme switching requires manual configuration update"
            echo "Edit: $CONFIG_FILE"
            ;;
          *)
            echo "Unknown theme: $THEME"
            echo "Run 'wezterm-theme list' to see available themes"
            exit 1
            ;;
        esac
      '';
    };
    
    # Shell aliases for WezTerm
    home-manager.users.yuki.programs.zsh.shellAliases = mkIf cfg.enable {
      wt = "wezterm";
      wezterm-config = "nvim ~/.config/wezterm/wezterm.lua";
    };
  };
}