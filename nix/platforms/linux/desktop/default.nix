# Linux Desktop Configuration
{ config, lib, pkgs, platformInfo, ... }:

{
  # Linux-specific system packages
  home.packages = with pkgs; platformInfo.filterForPlatform [
    # GUI applications for Linux
    firefox
    thunderbird
    
    # Development tools
    vscode
    
    # System utilities
    networkmanager
    pulseaudio
    
    # Desktop environment tools
    xorg.xrandr
    xorg.xdpyinfo
    
    # Font management
    fontconfig
    
    # Window management (for non-NixOS systems)
    i3
    rofi
    dunst
    
    # Media tools
    vlc
    
    # Archive managers
    unrar
    p7zip
    
    # Terminal emulators
    alacritty
    kitty
    
    # File managers
    ranger
    
    # System monitoring
    iotop
    nethogs
  ];

  # Linux-specific services
  services = lib.mkIf platformInfo.capabilities.canManageServices {
    # SSH agent
    ssh-agent.enable = true;
    
    # GPG agent
    gpg-agent = {
      enable = true;
      enableSshSupport = true;
    };
    
    # Desktop notifications
    dunst = lib.mkIf (lib.elem pkgs.dunst config.home.packages) {
      enable = true;
      settings = {
        global = {
          geometry = "300x5-30+20";
          transparency = 10;
          frame_color = "#89b4fa";
          font = "JetBrains Mono 10";
        };
      };
    };
  };

  # XDG configuration
  xdg = {
    enable = true;
    
    # MIME associations
    mimeApps = {
      enable = true;
      defaultApplications = {
        "text/html" = "firefox.desktop";
        "x-scheme-handler/http" = "firefox.desktop";
        "x-scheme-handler/https" = "firefox.desktop";
        "x-scheme-handler/about" = "firefox.desktop";
        "x-scheme-handler/unknown" = "firefox.desktop";
        "application/pdf" = "firefox.desktop";
        "text/plain" = "code.desktop";
        "application/json" = "code.desktop";
      };
    };
    
    # Desktop entries
    desktopEntries = {
      dotfiles = {
        name = "Dotfiles";
        comment = "Edit dotfiles configuration";
        exec = "code ~/dotfiles";
        icon = "folder-development";
        categories = [ "Development" ];
      };
    };
  };

  # Font configuration
  fonts.fontconfig.enable = true;

  # Qt and GTK theme
  qt = {
    enable = true;
    platformTheme = "gtk";
    style.name = "adwaita-dark";
  };

  gtk = {
    enable = true;
    theme = {
      name = "Catppuccin-Mocha-Standard-Blue-Dark";
      package = pkgs.catppuccin-gtk.override {
        accents = [ "blue" ];
        variant = "mocha";
      };
    };
    
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
  };

  # Session variables for Linux
  home.sessionVariables = {
    # Qt settings
    QT_QPA_PLATFORMTHEME = "gtk2";
    
    # GTK settings
    GTK_THEME = "Catppuccin-Mocha-Standard-Blue-Dark";
    
    # Font settings
    FONTCONFIG_FILE = "${config.xdg.configHome}/fontconfig/fonts.conf";
    
    # Desktop settings
    XDG_CURRENT_DESKTOP = "i3";
    
    # Development environment
    BROWSER = "firefox";
  };

  # Desktop files for window management
  home.file = {
    ".config/i3/config".text = ''
      # i3 configuration for Linux dotfiles setup
      set $mod Mod4
      
      # Font for window titles
      font pango:JetBrains Mono 10
      
      # Start a terminal
      bindsym $mod+Return exec alacritty
      
      # Kill focused window
      bindsym $mod+Shift+q kill
      
      # Start rofi
      bindsym $mod+d exec rofi -show drun
      
      # Change focus
      bindsym $mod+j focus left
      bindsym $mod+k focus down
      bindsym $mod+l focus up
      bindsym $mod+semicolon focus right
      
      # Move focused window
      bindsym $mod+Shift+j move left
      bindsym $mod+Shift+k move down
      bindsym $mod+Shift+l move up
      bindsym $mod+Shift+semicolon move right
      
      # Split orientation
      bindsym $mod+h split h
      bindsym $mod+v split v
      
      # Fullscreen mode
      bindsym $mod+f fullscreen toggle
      
      # Workspaces
      bindsym $mod+1 workspace number 1
      bindsym $mod+2 workspace number 2
      bindsym $mod+3 workspace number 3
      bindsym $mod+4 workspace number 4
      bindsym $mod+5 workspace number 5
      
      # Move to workspaces
      bindsym $mod+Shift+1 move container to workspace number 1
      bindsym $mod+Shift+2 move container to workspace number 2
      bindsym $mod+Shift+3 move container to workspace number 3
      bindsym $mod+Shift+4 move container to workspace number 4
      bindsym $mod+Shift+5 move container to workspace number 5
      
      # Reload/restart
      bindsym $mod+Shift+c reload
      bindsym $mod+Shift+r restart
      
      # Exit i3
      bindsym $mod+Shift+e exec "i3-nagbar -t warning -m 'Exit i3?' -B 'Yes' 'i3-msg exit'"
      
      # Status bar
      bar {
        status_command i3status
        position top
        colors {
          background #1e1e2e
          statusline #cdd6f4
          separator #6c7086
          
          focused_workspace  #89b4fa #89b4fa #1e1e2e
          active_workspace   #6c7086 #6c7086 #cdd6f4
          inactive_workspace #313244 #313244 #cdd6f4
          urgent_workspace   #f38ba8 #f38ba8 #1e1e2e
        }
      }
      
      # Window colors (Catppuccin Mocha)
      client.focused          #89b4fa #89b4fa #1e1e2e #f9e2af   #89b4fa
      client.focused_inactive #6c7086 #6c7086 #cdd6f4 #6c7086   #6c7086
      client.unfocused        #313244 #313244 #cdd6f4 #313244   #313244
      client.urgent           #f38ba8 #f38ba8 #1e1e2e #f38ba8   #f38ba8
    '';
  };
}