# SketchyBar Status Bar Configuration
# Complete falleco/dotfiles configuration with AeroSpace integration
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.statusbar.sketchybar;
in
{
  options.dotfiles.statusbar.sketchybar = {
    enable = mkEnableOption "SketchyBar status bar";
    
    configDir = mkOption {
      type = types.path;
      default = ../../../configs/wm/sketchybar;
      description = "Path to SketchyBar configuration directory";
    };
  };

  config = mkIf cfg.enable {
    # Install SketchyBar and dependencies via Homebrew
    homebrew.taps = [ "FelixKratz/formulae" ];
    homebrew.brews = [ 
      "lua"           # Required for Lua-based configuration
      "sketchybar"    # SketchyBar from FelixKratz tap
    ];
    
    # Link configuration directory
    home-manager.users.yuki.home.file.".config/sketchybar" = {
      source = cfg.configDir;
      recursive = true;
    };
    
    # SketchyBar health check script
    home-manager.users.yuki.home.file."bin/sketchybar-health" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        echo "📊 SketchyBar Status (falleco/dotfiles)"
        echo "======================================"
        
        # Check if SketchyBar is installed
        if command -v sketchybar &> /dev/null; then
          echo "✅ SketchyBar: Installed"
        else
          echo "❌ SketchyBar: Not installed"
          return 1
        fi
        
        # Check if SketchyBar is running
        if pgrep -x "sketchybar" > /dev/null; then
          echo "✅ SketchyBar: Running"
        else
          echo "⚠️  SketchyBar: Not running"
        fi
        
        # Check Lua configuration
        if [[ -f "$HOME/.config/sketchybar/sketchybarrc" ]]; then
          echo "✅ Configuration: Lua-based (falleco style)"
        else
          echo "❌ Configuration: Missing"
        fi
        
        # Check helpers build status
        if [[ -f "$HOME/.config/sketchybar/helpers/event_providers/cpu_load/bin/cpu_load" ]]; then
          echo "✅ CPU Provider: Built"
        else
          echo "⚠️  CPU Provider: Not built"
        fi
        
        if [[ -f "$HOME/.config/sketchybar/helpers/menus/bin/menus" ]]; then
          echo "✅ Menu Helper: Built"
        else
          echo "⚠️  Menu Helper: Not built"
        fi
        
        # Check AeroSpace integration
        if command -v aerospace &> /dev/null; then
          echo "✅ AeroSpace: Available for integration"
        else
          echo "⚠️  AeroSpace: Not available"
        fi
        
        # Check Lua availability
        if command -v lua &> /dev/null; then
          echo "✅ Lua: $(lua -v | head -1)"
        else
          echo "⚠️  Lua: Not available"
        fi
      '';
    };
    
    # SketchyBar restart script
    home-manager.users.yuki.home.file."bin/sketchybar-restart" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        echo "🔄 Restarting SketchyBar..."
        
        # Kill SketchyBar if running
        if pgrep -x "sketchybar" > /dev/null; then
          echo "Stopping SketchyBar..."
          pkill -x "sketchybar"
          sleep 1
        fi
        
        # Start SketchyBar
        echo "Starting SketchyBar..."
        sketchybar --reload
        
        echo "✅ SketchyBar restarted"
      '';
    };
    
    # Shell aliases
    home-manager.users.yuki.programs.zsh.shellAliases = mkIf cfg.enable {
      sketchybar-reload = "sketchybar --reload";
      sketchybar-config = "nvim ~/.config/sketchybar/sketchybarrc";
    };
  };
}