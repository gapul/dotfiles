{ config, pkgs, username, homeDirectory, dotfilesDirectory, ... }:

{
  # System-wide packages
  environment.systemPackages = with pkgs; [
    # Core CLI tools
    git
    gh
    jq
    ripgrep
    tree
    
    # Terminal tools  
    tmux
    starship
    
    # Development tools
    neovim
    shellcheck
    make
    gnumake
    cmake
    
    # Language runtimes
    python312
    nodejs_20
    
    # System utilities
    mas  # Mac App Store CLI
    
    # Optional: Yabai ecosystem (if available in nixpkgs)
    # yabai
    # skhd
    # Note: May need to use overlays or keep in Homebrew
  ];

  # Fonts
  fonts.packages = with pkgs; [
    (nerdfonts.override { fonts = [ "Hack" "FiraCode" "JetBrainsMono" ]; })
    # Add Japanese fonts if available
  ];

  # System preferences
  system = {
    defaults = {
      dock = {
        autohide = true;
        autohide-delay = 0.0;
        autohide-time-modifier = 0.2;
        expose-animation-duration = 0.1;
        launchanim = false;
        minimize-to-application = true;
        mouse-over-hilite-stack = true;
        show-recents = false;
        static-only = true;
        tilesize = 48;
      };

      finder = {
        AppleShowAllExtensions = true;
        AppleShowAllFiles = true;
        CreateDesktop = false;
        FXDefaultSearchScope = "SCcf"; # Search current folder
        FXEnableExtensionChangeWarning = false;
        FXPreferredViewStyle = "Nlsv"; # List view
        QuitMenuItem = true;
        ShowPathbar = true;
        ShowStatusBar = true;
      };

      loginwindow = {
        DisableConsoleAccess = true;
        GuestEnabled = false;
      };

      NSGlobalDomain = {
        AppleInterfaceStyle = "Dark";
        AppleKeyboardUIMode = 3; # Full keyboard access
        ApplePressAndHoldEnabled = false; # Disable press-and-hold for special characters
        AppleShowAllExtensions = true;
        AppleShowScrollBars = "WhenScrolling";
        InitialKeyRepeat = 15; # Fast key repeat
        KeyRepeat = 2; # Very fast key repeat
        NSAutomaticCapitalizationEnabled = false;
        NSAutomaticDashSubstitutionEnabled = false;
        NSAutomaticPeriodSubstitutionEnabled = false;
        NSAutomaticQuoteSubstitutionEnabled = false;
        NSAutomaticSpellingCorrectionEnabled = false;
        NSDocumentSaveNewDocumentsToCloud = false;
        NSNavPanelExpandedStateForSaveMode = true;
        NSNavPanelExpandedStateForSaveMode2 = true;
      };

      trackpad = {
        Clicking = true; # Tap to click
        TrackpadRightClick = true;
        TrackpadThreeFingerDrag = true;
      };

      # Custom user defaults
      CustomUserPreferences = {
        "com.apple.desktopservices" = {
          DSDontWriteNetworkStores = true; # Disable .DS_Store on network drives
          DSDontWriteUSBStores = true; # Disable .DS_Store on USB drives
        };
        "com.apple.screensaver" = {
          askForPassword = 1;
          askForPasswordDelay = 0;
        };
        "com.apple.TimeMachine" = {
          DoNotOfferNewDisksForBackup = true;
        };
      };
    };

    # Keyboard remapping
    keyboard = {
      enableKeyMapping = true;
      remapCapsLockToEscape = true;
    };

    # System version (automatically managed)
    stateVersion = 5;
  };

  # Shell configuration
  programs.zsh.enable = true;
  environment.shells = [ pkgs.zsh ];

  # Services
  services = {
    # Nix daemon
    nix-daemon.enable = true;
    
    # Optional: Custom services
    # Note: Yabai, skhd, sketchybar services may need custom configuration
  };

  # Nix configuration
  nix = {
    package = pkgs.nix;
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      extra-platforms = [ "x86_64-darwin" "aarch64-darwin" ];
      trusted-users = [ "@admin" username ];
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      interval = { Weekday = 0; Hour = 2; Minute = 0; };
      options = "--delete-older-than 30d";
    };
  };

  # User configuration
  users.users.${username} = {
    name = username;
    home = homeDirectory;
    shell = pkgs.zsh;
  };

  # Security
  security.pam.enableSudoTouchId = true;

  # Homebrew (for packages not available in nixpkgs)
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      cleanup = "zap";
      upgrade = false;
    };
    
    # Packages that must remain in Homebrew
    taps = [
      "koekeishiya/formulae"  # yabai, skhd
      "felixkratz/formulae"   # sketchybar
    ];
    
    brews = [
      "yabai"
      "skhd" 
      "sketchybar"
    ];
    
    casks = [
      # GUI applications that are better managed via Homebrew
      "wezterm"  # May move to nix later
      
      # Applications not available in nixpkgs
      "raycast"
      "karabiner-elements"
      
      # Temporary: Keep critical apps in Homebrew during transition
      "visual-studio-code"
      "docker"
    ];
    
    masApps = {
      # Mac App Store applications
      # "Xcode" = 497799835;
    };
  };
}