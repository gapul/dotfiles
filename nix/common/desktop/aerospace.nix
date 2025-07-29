# AeroSpace Window Manager Configuration
# Tiling window manager for macOS
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.desktop.aerospace;
in
{
  options.dotfiles.desktop.aerospace = {
    enable = mkEnableOption "AeroSpace window manager";
    
    configFile = mkOption {
      type = types.path;
      default = ../../../configs/wm/aerospace/aerospace.toml;
      description = "Path to aerospace configuration file";
    };
  };

  config = mkIf cfg.enable {
    # Install AeroSpace via Homebrew (not available in nixpkgs)
    homebrew.casks = [ "aerospace" ];
    
    # Link configuration file
    home-manager.users.yuki.home.file.".config/aerospace/aerospace.toml" = {
      source = cfg.configFile;
    };
    
    # AeroSpace service management
    home-manager.users.yuki.home.file."bin/aerospace-health" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        echo "🪟 AeroSpace Window Manager Status"
        echo "================================="
        
        # Check if AeroSpace is installed
        if command -v aerospace &> /dev/null; then
          echo "✅ AeroSpace: Installed"
          echo "   Version: $(aerospace --version)"
        else
          echo "❌ AeroSpace: Not installed"
          return 1
        fi
        
        # Check if AeroSpace is running
        if pgrep -x "AeroSpace" > /dev/null; then
          echo "✅ AeroSpace: Running"
        else
          echo "⚠️  AeroSpace: Not running"
        fi
        
        # Check configuration file
        if [[ -f "$HOME/.config/aerospace/aerospace.toml" ]]; then
          echo "✅ Configuration: Found"
        else
          echo "❌ Configuration: Missing"
        fi
        
        # Check workspace count
        if command -v aerospace &> /dev/null && pgrep -x "AeroSpace" > /dev/null; then
          local workspaces=$(aerospace list-workspaces | wc -l | tr -d ' ')
          echo "📊 Workspaces: $workspaces configured"
        fi
      '';
    };
    
    # Quick restart script
    home-manager.users.yuki.home.file."bin/aerospace-restart" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        echo "🔄 Restarting AeroSpace..."
        
        # Kill AeroSpace if running
        if pgrep -x "AeroSpace" > /dev/null; then
          echo "Stopping AeroSpace..."
          pkill -x "AeroSpace"
          sleep 2
        fi
        
        # Start AeroSpace
        echo "Starting AeroSpace..."
        open -a AeroSpace
        
        echo "✅ AeroSpace restarted"
      '';
    };
  };
}