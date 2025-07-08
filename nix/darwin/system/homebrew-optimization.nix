# Homebrew optimization strategy for macOS
{ lib, ... }:

{
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;    # Controlled updates
      cleanup = "zap";       # Remove unused packages
      upgrade = false;       # Manual upgrades for stability
    };
    
    # Specialized taps for unique software
    taps = [
      "nikitabobko/tap"       # AeroSpace (tiling window manager)
      "felixkratz/formulae"   # SketchyBar (status bar)
    ];
    
    # ONLY formulae that cannot be replaced by Nix
    brews = [
      "sketchybar"           # macOS status bar (requires Homebrew for integration)
      # All other formulae migrated to Nix
    ];
    
    # GUI applications and macOS-native software
    casks = [
      # Essential productivity
      "raycast" "karabiner-elements"
      
      # Development (native macOS versions)
      "cursor" "visual-studio-code" "zed" "wezterm"
      
      # Creative tools (optimized for macOS)
      "figma" "blender" "gimp" "inkscape"
      
      # Specialized tools requiring native integration
      "aerospace" "voicevox" "battery"
      
      # Gaming and entertainment
      "steam" "retroarch-metal"
      
      # Fonts (Nerd Fonts for development)
      "font-hackgen-nerd" "font-sf-mono" "font-sf-pro"
    ];
    
    # Mac App Store integration
    masApps = {
      "Xcode" = 497799835;        # Required for iOS development
      "GarageBand" = 682658836;   # Music production
      "Bitwarden" = 1352778147;   # Password manager
    };
  };
}