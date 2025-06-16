{ config, pkgs, username, homeDirectory, dotfilesDirectory, ... }:

{
  # System-wide packages (CLI tools + ALL GUI applications)
  environment.systemPackages = with pkgs; [
    # Core CLI tools that definitely work
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
    
    # System utilities
    mas  # Mac App Store CLI
    htop
    btop
    
    # Essential tools
    nmap
    ncdu        # Disk usage analyzer
    lsof        # List open files
    watch       # Execute programs periodically
    
    # Network tools
    nss         # Network Security Services
    tcpdump     # Network packet analyzer
    
    # Archive tools
    p7zip       # 7-Zip archive tool
    unar        # Archive extraction tool
    
    # Text processing
    jq          # JSON processor
    yq          # YAML processor
    pandoc      # Document converter
    
    # Window management packages (for manual installation)
    # Note: yabai, skhd, sketchybar services configured below
    
    # CORE APPLICATIONS - Apple Silicon Compatible Only
    # Development & Programming (verified compatible)
    docker          # Container runtime
    vscode          # Visual Studio Code
    zed-editor      # Modern text editor
    # virtualbox    # Not supported on Apple Silicon - keeping in Homebrew
    # podman-desktop # Potential compatibility issues - keeping in Homebrew
    # godot_4       # Not supported on Apple Silicon - keeping in Homebrew
    # freecad       # Not supported on Apple Silicon - keeping in Homebrew
    # kicad         # Potential compatibility issues - keeping in Homebrew
    # goxel         # Potential compatibility issues - keeping in Homebrew
    
    # Browsers (verified compatible)
    firefox         # Web browser
    firefox-devedition # Firefox Developer Edition
    floorp          # Privacy-focused browser
    # vivaldi       # Excluded per user request
    tor-browser     # Privacy browser
    
    # Creative & Design (conservative selection)
    # gimp          # Potential compatibility issues - keeping in Homebrew
    # inkscape      # Potential compatibility issues - keeping in Homebrew
    # krita         # Potential compatibility issues - keeping in Homebrew
    # blender       # Potential compatibility issues - keeping in Homebrew
    # scribus       # Potential compatibility issues - keeping in Homebrew
    # fontforge     # Potential compatibility issues - keeping in Homebrew
    # natron        # Potential compatibility issues - keeping in Homebrew
    # opentoonz     # Potential compatibility issues - keeping in Homebrew
    
    # Media & Entertainment (conservative selection)
    # vlc           # Not supported on Apple Silicon - keeping in Homebrew
    # obs-studio    # Not supported on Apple Silicon - keeping in Homebrew
    # musescore     # Potential compatibility issues - keeping in Homebrew
    # mixxx         # Potential compatibility issues - keeping in Homebrew
    # surge-XT      # Potential compatibility issues - keeping in Homebrew
    
    # Gaming & Emulation (conservative selection)
    # steam         # Potential compatibility issues - keeping in Homebrew
    minecraft       # Minecraft Java Edition
    # retroarch     # Potential compatibility issues - keeping in Homebrew
    # prismlauncher # Potential compatibility issues - keeping in Homebrew
    
    # Office & Productivity (verified compatible)
    libreoffice     # Office suite
    # onlyoffice-bin # Potential compatibility issues - keeping in Homebrew
    thunderbird     # Email client
    obsidian        # Knowledge management
    zotero          # Reference manager
    
    # Utilities & System (conservative selection)
    bitwarden-desktop # Password manager
    espanso         # Text expander
    syncthing       # File synchronization
    # spacedrive    # Potential compatibility issues - keeping in Homebrew
    # rustdesk      # Potential compatibility issues - keeping in Homebrew
    # wireshark     # Potential compatibility issues - keeping in Homebrew
    qbittorrent     # Torrent client
    wezterm         # Modern terminal emulator
    
    # Professional Tools (conservative selection)
    # davinci-resolve # Potential compatibility issues - keeping in Homebrew
    # zrythm        # Potential compatibility issues - keeping in Homebrew
    
    # AI & Development (verified compatible)
    ollama          # Local LLM runner
    
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
      };

      trackpad = {
        Clicking = true;
        TrackpadRightClick = true;
        TrackpadThreeFingerDrag = true;
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

  # Nix configuration
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      # Remove problematic settings
      # parallel-shell-jobs = 4;
      max-jobs = "auto";
      cores = 0;
      substituters = [
        "https://cache.nixos.org/"
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
      # auto-optimise-store = true;  # Moved to nix.optimise.automatic
    };
    
    # Use the correct setting for store optimization
    optimise = {
      automatic = true;
    };
  };

  # Allow unfree packages for GUI applications
  nixpkgs.config.allowUnfree = true;

  # User configuration
  users.users.${username} = {
    name = username;
    home = homeDirectory;
    shell = pkgs.zsh;
  };

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
      
      # Creative & Design
      "gimp"
      "inkscape"
      "krita"
      "blender"
      "scribus"
      "fontforge"
      "natron"
      "opentoonz"
      
      # Media & Entertainment
      "vlc"
      "obs"
      "musescore"
      "mixxx"
      "surge-xt"
      
      # Gaming & Emulation
      "steam"
      "retroarch-metal"
      "prismlauncher"
      
      # Office & Productivity
      "onlyoffice"
      
      # Utilities & System
      "spacedrive"
      "rustdesk"
      "wireshark"
      
      # Professional Tools
      "davinci-resolve"
      "zrythm"
      
      # Browsers (special editions only)
      "zen"
      "google-chrome@dev"
      "vivaldi"        # Moved from nix per user request
      
      # Gaming & Entertainment (platform-specific)
      "epic-games"
      "whisky"
      
      # Utilities & System (macOS-specific tools)
      "shortcat"
      "middleclick"
      "jordanbaird-ice"
      "cloudflare-warp"
      "vmware-fusion"
      
      # Office & Documents (Microsoft Office native)
      "microsoft-excel"
      "microsoft-word"
      "microsoft-powerpoint"
      
      # AI & Assistant tools (native apps)
      "claude"
      "chatgpt"
      
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
    };
  };
}