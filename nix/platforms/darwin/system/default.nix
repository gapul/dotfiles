{ config, pkgs, username, homeDirectory, dotfilesDirectory, ... }:

{
  imports = [
    ../../common/system/optimization.nix
    ../../common/system/maintenance.nix
  ];
  
  # Enable system optimization
  dotfiles.system.optimization = {
    enable = true;
    nixBuildOptimization = true;
    macOSOptimization = true;
    performanceProfiles = "balanced";
  };
  
  # Enable system maintenance
  dotfiles.system.maintenance = {
    enable = true;
    autoGarbageCollection = true;
    autoOptimization = true;
    retentionDays = 30;
  };
  # SOPS secrets management configuration
  sops = {
    defaultSopsFile = ../secrets.yaml;
    defaultSopsFormat = "yaml";
    
    # Age key for encryption/decryption
    age = {
      # Generate with: age-keygen -o ~/.config/sops/age/keys.txt
      keyFile = "${homeDirectory}/.config/sops/age/keys.txt";
      generateKey = true;
    };
    
    # Define secrets that will be decrypted and placed in the system
    secrets = {
      # Example secret definitions (uncomment when secrets.yaml exists)
      # "github_token" = {
      #   path = "/run/secrets/github_token";
      #   owner = username;
      #   group = "staff";
      #   mode = "0400";
      # };
      # "openai_api_key" = {
      #   path = "/run/secrets/openai_api_key";
      #   owner = username;
      #   group = "staff";
      #   mode = "0400";
      # };
    };
  };
  # System-wide packages (CLI tools + ALL GUI applications)
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
    gnutar
    rsync
    
    # Terminal tools  
    tmux
    starship
    zoxide  # Smart cd replacement
    direnv
    lazygit  # Git TUI
    gitui    # Alternative Git TUI
    delta    # Git diff tool
    
    # Development tools
    neovim
    vim
    shellcheck
    gnumake
    cmake
    curl
    wget
    openssh
    
    # Language runtimes & tools
    python312
    nodejs_20
    go
    rustc
    cargo
    
    # Development utilities
    docker
    docker-compose
    
    # Secret management tools
    sops
    age
    
    # System utilities
    mas  # Mac App Store CLI
    htop
    btop
    bottom   # System monitor
    procs    # Modern ps replacement
    dust     # Modern du replacement
    
    # Essential tools
    nmap
    ncdu        # Disk usage analyzer
    lsof        # List open files
    watch       # Execute programs periodically
    
    # Network tools
    nss         # Network Security Services
    tcpdump     # Network packet analyzer
    bandwhich   # Network bandwidth monitor
    
    # Archive tools
    p7zip       # 7-Zip archive tool
    unar        # Archive extraction tool
    
    # Text processing
    jq          # JSON processor
    yq          # YAML processor
    pandoc      # Document converter
    
    # Modern CLI replacements
    sd          # Modern sed replacement
    tokei       # Code statistics
    tealdeer    # Modern man pages (tldr)
    hyperfine   # Benchmarking tool
    
    # File operations
    rename      # Rename utility
    
    # GUI applications available in nixpkgs (better performance & reproducibility)
    chromium         # Open source Chrome
    libreoffice      # Office suite
    gimp             # Image editing
    inkscape         # Vector graphics
    vlc              # Media player
    obs-studio       # Screen recording/streaming
    discord          # Communication
    slack            # Team communication
    vscode           # Code editor
    
    # Note: Many GUI apps still managed by Homebrew for better macOS integration
    
  ];

  # Fonts (basic set)
  fonts.packages = with pkgs; [
    nerd-fonts.hack
    nerd-fonts.fira-code
    nerd-fonts.jetbrains-mono
  ];

  # System preferences
  system = {
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
        FXDefaultSearchScope = "SCcf";
        FXEnableExtensionChangeWarning = false;
        FXPreferredViewStyle = "Nlsv";
        QuitMenuItem = true;
        ShowPathbar = true;
        ShowStatusBar = true;
      };

      NSGlobalDomain = {
        AppleInterfaceStyle = "Dark";
        AppleKeyboardUIMode = 3;
        ApplePressAndHoldEnabled = false;
        AppleShowAllExtensions = true;
        AppleShowScrollBars = "WhenScrolling";
        InitialKeyRepeat = 15;
        KeyRepeat = 2;
        NSAutomaticCapitalizationEnabled = false;
        NSAutomaticDashSubstitutionEnabled = false;
        NSAutomaticPeriodSubstitutionEnabled = false;
        NSAutomaticQuoteSubstitutionEnabled = false;
        NSAutomaticSpellingCorrectionEnabled = false;
        NSDocumentSaveNewDocumentsToCloud = false;
        NSNavPanelExpandedStateForSaveMode = true;
        NSNavPanelExpandedStateForSaveMode2 = true;
        
        # Note: Trackpad settings managed via system.defaults.trackpad section below
      };

      trackpad = {
        # Basic trackpad settings (nix-darwin supported options only)
        Clicking = false;  # Disable tap to click
        TrackpadRightClick = true;  # Enable two-finger right click
        TrackpadThreeFingerDrag = true;  # Keep three finger drag
      };
    };

    keyboard = {
      enableKeyMapping = true;
      remapCapsLockToEscape = true;
    };

    stateVersion = 5;
  };

  # Shell configuration
  programs.zsh.enable = true;
  environment.shells = [ pkgs.zsh ];

  # Nix configuration - Disabled for Determinate Nix compatibility
  nix.enable = false;

  # Allow unfree packages for GUI applications
  nixpkgs.config.allowUnfree = true;

  # User configuration
  users.users.${username} = {
    name = username;
    home = homeDirectory;
    shell = pkgs.zsh;
  };

# Note: Mac App Store management moved back to homebrew.masApps

  # Homebrew (for all GUI apps and problematic packages)
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      cleanup = "zap";
      upgrade = false;
    };
    
    taps = [
      "koekeishiya/formulae"  # yabai, skhd
      "felixkratz/formulae"   # sketchybar
    ];
    
    brews = [
      # Window management (requires Homebrew for proper macOS integration)
      "yabai"
      "skhd" 
      "sketchybar"
    ];
    
    casks = [
      # Core productivity (macOS-specific tools only) 
      "raycast"
      "karabiner-elements"
      
      # Development & Programming
      "cursor"
      "unity-hub"
      "material-maker"
      "virtualbox"    # VirtualBox (Apple Silicon limitations)
      "godot"         # Godot (Apple Silicon limitations)
      "podman-desktop" # Container management
      "freecad"       # CAD software  
      "kicad"         # PCB design
      "goxel"         # Voxel editor
      
      # Creative & Design (macOS-specific versions only)
      "krita"
      "blender"
      "scribus"
      "fontforge"
      "natron"
      "opentoonz"
      
      # Media & Entertainment (macOS-specific versions only)
      "musescore"
      "mixxx" 
      "surge-xt"
      
      # Gaming & Emulation
      "steam"
      "retroarch-metal"
      "prismlauncher"
      "epic-games"
      "whisky"
      "minecraft"
      
      # Office & Productivity (macOS-specific versions only)
      "onlyoffice"
      "microsoft-excel"
      "microsoft-word"
      "microsoft-powerpoint"
      
      # Utilities & System
      "spacedrive"
      "rustdesk"
      "wireshark"
      "shortcat"
      "middleclick"
      "jordanbaird-ice"
      "cloudflare-warp"
      "vmware-fusion"
      "syncthing"
      "espanso"
      
      # Professional Tools
      # Note: DaVinci Resolve and Zrythm not available in Homebrew casks
      
      # Browsers (special editions and macOS-optimized versions)
      "zen"
      "google-chrome@dev"
      "vivaldi"
      "floorp"
      "firefox@developer-edition"
      "tor-browser"
      # Note: Firefox and Thunderbird not managed by dotfiles
      
      # Communication & Social (native macOS apps only)
      # "discord" moved to nix
      # "slack" moved to nix
      
      # AI & Assistant tools (native apps)
      "claude"
      "chatgpt"
      "ollama"
      
      # Development Tools & Editors (macOS-specific versions only)
      "zed"
      "wezterm"
      # "visual-studio-code" moved to nix
      
      # Research & Knowledge Management
      "obsidian"
      "zotero"
      
      # Media & Security
      
      # Fonts (Japanese/special fonts)
      "font-hackgen-nerd"
      "font-udev-gothic-nf"
      "font-plemol-jp-nf"
      "font-cica"
      "font-hack-nerd-font"
      "font-sf-mono"
      "font-sf-pro"
      "sf-symbols"
    ];
    
    masApps = {
      # Core Mac App Store applications
      "GarageBand" = 682658836;
      "LINE" = 539883307;
      "Bitwarden" = 1352778147;
      "Xcode" = 497799835;
    };
  };
}