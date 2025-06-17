# NixOS Home Manager Configuration
{ config, lib, pkgs, platformInfo, ... }:

{
  # Import common configurations
  imports = [
    ../../common/home/shell.nix
    ../../common/themes/default.nix
  ];

  # Basic settings
  home.username = "yuki";
  home.homeDirectory = "/home/yuki";
  home.stateVersion = "23.11";

  # NixOS-specific packages
  home.packages = with pkgs; platformInfo.filterForPlatform [
    # Development tools
    vscode
    
    # System utilities
    htop
    tree
    
    # Media tools
    vlc
    
    # Archive managers
    unrar
    p7zip
    
    # Terminal emulators
    kitty
    
    # File managers
    ranger
  ];

  # XDG configuration
  xdg = {
    enable = true;
    
    mimeApps = {
      enable = true;
      defaultApplications = {
        "text/html" = "firefox.desktop";
        "x-scheme-handler/http" = "firefox.desktop";
        "x-scheme-handler/https" = "firefox.desktop";
        "application/pdf" = "firefox.desktop";
        "text/plain" = "code.desktop";
      };
    };
  };

  # Font configuration
  fonts.fontconfig.enable = true;

  # Qt and GTK theme
  qt = {
    enable = true;
    platformTheme.name = "gtk";
    style.name = "adwaita-dark";
  };

  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
  };

  # Services
  services = {
    # SSH agent
    ssh-agent.enable = true;
    
    # GPG agent
    gpg-agent = {
      enable = true;
      enableSshSupport = true;
    };
  };

  # Session variables
  home.sessionVariables = {
    BROWSER = "firefox";
    XDG_CURRENT_DESKTOP = "i3";
  };

  # Programs
  programs.home-manager.enable = true;
}