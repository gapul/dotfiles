# Color Definitions - Pure Configuration Values
# No home-manager options, just color definitions for use in other modules

{
  # Catppuccin color scheme definitions
  colors = {
    # String format for CSS/config files
    str = {
      dark = {
        base = "#1e1e2e";        # Background
        mantle = "#181825";      # Secondary background  
        surface0 = "#313244";    # Surface
        text = "#cdd6f4";        # Main text
        
        # Accent colors
        red = "#f38ba8";         # Error/danger
        green = "#a6e3a1";       # Success
        blue = "#89b4fa";        # Info/primary
        yellow = "#f9e2af";      # Warning
        peach = "#fab387";       # Orange accent
        
        # Semantic colors
        cursor = "#89b4fa";      # Cursor color
        selection = "#313244";   # Selection background
        border = "#6c7086";      # Border color
      };
      
      light = {
        base = "#eff1f5";        # Background
        mantle = "#e6e9ef";      # Secondary background
        surface0 = "#ccd0da";    # Surface
        text = "#4c4f69";        # Main text
        
        # Accent colors (adjusted for light theme)
        red = "#d20f39";         # Error/danger
        green = "#40a02b";       # Success
        blue = "#1e66f5";        # Info/primary
        yellow = "#df8e1d";      # Warning
        peach = "#fe640b";       # Orange accent
        
        # Semantic colors
        cursor = "#1e66f5";      # Cursor color
        selection = "#ccd0da";   # Selection background
        border = "#bcc0cc";      # Border color
      };
    };
    
    # Integer format for Lua applications (sketchybar)
    int = {
      dark = {
        base = "0xff1e1e2e";
        mantle = "0xff181825";
        surface0 = "0xff313244";
        text = "0xffcdd6f4";
        blue = "0xff89b4fa";
        green = "0xffa6e3a1";
        red = "0xfff38ba8";
        yellow = "0xfff9e2af";
        peach = "0xfffab387";
        transparent = "0x00000000";
      };
      light = {
        base = "0xffeff1f5";
        mantle = "0xffe6e9ef";
        surface0 = "0xffccd0da";
        text = "0xff4c4f69";
        blue = "0xff1e66f5";
        green = "0xff40a02b";
        red = "0xffd20f39";
        yellow = "0xffdf8e1d";
        peach = "0xfffe640b";
        transparent = "0x00000000";
      };
    };
  };

  # Typography settings
  typography = {
    # Monospace fonts for terminal and code
    monospace = {
      name = "HackGen Console NF";
      size = 14;
      fallbacks = [ "SF Mono" "Menlo" "Monaco" "DejaVu Sans Mono" ];
    };
    
    # UI fonts for interface
    ui = {
      name = "SF Pro Display";
      size = 13;
      fallbacks = [ "Helvetica Neue" "Arial" "sans-serif" ];
    };
    
    # Japanese fonts
    japanese = {
      name = "HackGen Console NF";
      size = 14;
      fallbacks = [ "Hiragino Sans" "Noto Sans CJK JP" ];
    };
  };

  # Spacing and layout
  spacing = {
    # Window management
    windowGap = 8;
    screenPadding = 16;
    
    # UI elements  
    barHeight = 32;
    borderWidth = 2;
    borderRadius = 8;
    padding = 8;
    margin = 4;
  };
  
  # Editor configurations
  editor = {
    font = "HackGen Console NF";
    fontSize = 14;
    lineHeight = 1.2;
    tabSize = 2;
    colorTheme = "Catppuccin";
  };

  # Theme switching
  themeMode = {
    default = "auto";  # auto, dark, light
    autoSwitch = true; # Follow system appearance
  };
}