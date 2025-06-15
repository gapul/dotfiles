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
    eza  # Modern ls replacement
    fd   # Modern find replacement
    bat  # Modern cat replacement
    fzf  # Fuzzy finder
    unzip
    gzip
    tar
    rsync
    
    # Terminal tools  
    tmux
    starship
    zoxide  # Smart cd replacement
    direnv
    
    # Development tools
    neovim
    vim
    shellcheck
    gnumake  # Use gnumake instead of make
    cmake
    curl
    wget
    openssh
    git-lfs
    
    # Language runtimes & tools
    python312
    python312Packages.pip
    python312Packages.virtualenv
    nodejs_20
    yarn
    go
    rustc
    cargo
    
    # Audio/Media development (from history)
    sox           # Audio processing
    libsndfile    # Audio file library
    
    # Font tools
    fontconfig
    
    # Text processing
    texlive.combined.scheme-full  # LaTeX (from history)
    
    # Development utilities
    docker
    docker-compose
    kubernetes
    kubectl
    terraform
    
    # System utilities
    mas  # Mac App Store CLI
    htop
    btop  # Modern htop
    watch
    coreutils
    findutils
    gnused
    gawk
    
    # Network tools
    nmap
    telnet
    netcat
    
    # Media tools
    ffmpeg
    imagemagick
    
    # Database tools
    sqlite
    postgresql
    redis
    
    # Cloud tools
    awscli2
    google-cloud-sdk
    
    # Optional: Yabai ecosystem (if available in nixpkgs)
    # yabai
    # skhd
    # Note: May need to use overlays or keep in Homebrew
  ];

  # Fonts (based on brew history)
  fonts.packages = with pkgs; [
    # Nerd Fonts from brew history
    nerd-fonts.hack-nerd-font      # HackGen Nerd Font base
    nerd-fonts.fira-code-nerd-font
    nerd-fonts.jetbrains-mono-nerd-font
    
    # Japanese fonts (from brew history)
    # Note: Some fonts may need to be installed via Homebrew casks
    # font-hackgen-nerd, font-udev-gothic-nf, font-plemoljp-nf, font-cica
  ];

  # System preferences
  system = {
    # Primary user (required for new nix-darwin)
    primaryUser = username;
    
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
    # nix-daemon is now managed automatically when nix.enable is true
    # nix-daemon.enable = true; # Deprecated in newer nix-darwin
    
    # Optional: Custom services
    # Note: Yabai, skhd, sketchybar services may need custom configuration
  };

  # Nix configuration (disabled for Determinate Nix compatibility)
  nix = {
    enable = false; # Disable nix-darwin's Nix management for Determinate Nix
    # package = pkgs.nix;
    # settings = {
    #   experimental-features = [ "nix-command" "flakes" ];
    #   extra-platforms = [ "x86_64-darwin" "aarch64-darwin" ];
    #   trusted-users = [ "@admin" username ];
    # };
    # optimise = {
    #   automatic = true; # Changed from auto-optimise-store
    # };
    # gc = {
    #   automatic = true;
    #   interval = { Weekday = 0; Hour = 2; Minute = 0; };
    #   options = "--delete-older-than 30d";
    # };
  };

  # User configuration
  users.users.${username} = {
    name = username;
    home = homeDirectory;
    shell = pkgs.zsh;
  };

  # Security
  # security.pam.enableSudoTouchId = true; # Not available in current nix-darwin

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
      # Core productivity applications
      "raycast"
      "karabiner-elements"
      "wezterm"
      "visual-studio-code"
      
      # Development tools
      "figma"           # Design tool (from history)
      "docker"          # Container platform
      "virtualbox"      # Virtualization (from history)
      
      # Communication & Productivity
      "line"            # Messaging app (installed)
      
      # Creative & Media
      "bitwarden"       # Password manager (installed)
      
      # AI & Assistant tools
      "claude"          # AI assistant (from history)
      "chatgpt"         # AI assistant (from history)
      
      # Japanese fonts (not available in nixpkgs)
      "font-hackgen-nerd"    # Japanese programming font
      "font-udev-gothic-nf"  # Japanese UI font
      "font-plemoljp-nf"     # Japanese programming font
      "font-cica"            # Japanese programming font
      
      # Development utilities
      "fontforge"       # Font editor (from history)
      
      # Optional: Add more as needed based on usage
    ];
    
    masApps = {
      # Mac App Store applications (based on actual usage)
      "GarageBand" = 682658836;  # Already installed
      "LINE" = 539883307;        # Communication app
      # Add more as needed based on actual usage
    };
  };
}