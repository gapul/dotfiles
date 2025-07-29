# Desktop Environment Configuration
# Window managers, desktop applications, and UI enhancements
{ config, lib, pkgs, ... }:

with lib;

{
  imports = [
    ./aerospace.nix
  ];

  options.dotfiles.desktop = {
    enable = mkEnableOption "Desktop environment configuration";
    
    profile = mkOption {
      type = types.enum [ "minimal" "standard" "full" ];
      default = "standard";
      description = "Desktop environment profile";
    };
  };

  config = mkIf config.dotfiles.desktop.enable {
    # Enable desktop components based on profile
    dotfiles.desktop.aerospace.enable = mkDefault (
      elem config.dotfiles.desktop.profile [ "standard" "full" ]
    );
    
    # Desktop applications (managed via Homebrew for better macOS integration)
    homebrew = mkIf (config.dotfiles.desktop.profile == "full") {
      casks = [
        # Development tools
        "visual-studio-code"
        "github-desktop"
        
        # Utilities
        "rectangle"  # Window management (alternative to AeroSpace)
        "alfred"     # Spotlight replacement
        "cleanmymac" # System maintenance
        
        # Media
        "vlc"
        "spotify"
        
        # Communication
        "slack"
        "discord"
        "zoom"
      ];
    };
  };
}