{ config, pkgs, username, homeDirectory, dotfilesDirectory, ... }:

{
  # System-wide packages (minimal, stable set)
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
    
    # Phase 4: GUI Applications migrated from Homebrew
    docker          # Container runtime
    firefox         # Web browser
    vlc             # Media player
    obs-studio      # Screen recording/streaming
    gimp            # Image editor
    inkscape        # Vector graphics editor
    krita           # Digital painting
    thunderbird     # Email client
    blender         # 3D modeling
    libreoffice     # Office suite
    qbittorrent     # Torrent client
    
    # Phase 5: Maximum Homebrew to Nix Migration (28 apps)
    # Development Tools
    vscode          # Visual Studio Code
    zed-editor      # Modern text editor
    virtualbox      # Virtualization platform
    podman-desktop  # Container management
    godot_4         # Game engine
    freecad         # CAD software
    kicad           # PCB design
    goxel           # Voxel editor
    
    # Creative Applications
    scribus         # Desktop publishing
    fontforge       # Font editor
    natron          # Compositing software
    opentoonz       # 2D animation
    
    # Browsers
    vivaldi         # Feature-rich browser
    tor-browser     # Privacy browser
    
    # Media Applications
    musescore       # Music notation
    mixxx           # DJ software
    surge-XT        # Synthesizer
    
    # Gaming
    prismlauncher   # Minecraft launcher
    
    # Productivity & Utilities
    obsidian        # Knowledge management
    zotero          # Reference manager
    bitwarden-desktop # Password manager
    espanso         # Text expander
    syncthing       # File synchronization
    spacedrive      # File manager
    rustdesk        # Remote desktop
    wireshark       # Network analyzer
    onlyoffice-bin  # Office suite
    ollama          # Local LLM runner
    
    # Phase 6: Additional Discovered Applications (1 app)
    # High-value applications actually found on system
    figma           # Design tool (discovered and verified installed)
    
    # Phase 7: Installed Apps Analysis (8 apps)
    # Professional and high-value applications found in /Applications
    davinci-resolve    # Professional video editing software
    firefox-devedition # Firefox Developer Edition
    floorp             # Privacy-focused browser
    minecraft          # Minecraft Java Edition
    retroarch          # Retro gaming emulator
    steam              # Gaming platform
    wezterm            # Modern terminal emulator
    zrythm             # Professional DAW
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
      auto-optimise-store = true;
    };
  };

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
      # Core productivity
      "raycast"
      "karabiner-elements"
      # "wezterm"       # Migrated to nix (Phase 7) - wezterm
      # "visual-studio-code"  # Migrated to nix (Phase 5) - vscode
      
      # Development & Programming
      "cursor"
      # "zed"           # Migrated to nix (Phase 5) - zed-editor
      # "figma"        # Migrated to nix (Phase 6) - figma
      # "docker"        # Migrated to nix (Phase 4)
      # "virtualbox"    # Migrated to nix (Phase 5)
      # "podman-desktop" # Migrated to nix (Phase 5)
      "unity-hub"
      # "godot"         # Migrated to nix (Phase 5) - godot_4
      # "freecad"       # Migrated to nix (Phase 5)
      # "kicad"         # Migrated to nix (Phase 5)
      # "goxel"         # Migrated to nix (Phase 5)
      
      # Creative & Design
      # "gimp"          # Migrated to nix (Phase 4)
      # "krita"         # Migrated to nix (Phase 4)  
      # "inkscape"      # Migrated to nix (Phase 4)
      # "scribus"       # Migrated to nix (Phase 5)
      # "fontforge"     # Migrated to nix (Phase 5)
      "material-maker"
      # "natron"        # Migrated to nix (Phase 5)
      # "opentoonz"     # Migrated to nix (Phase 5)
      
      # Browsers
      "zen"
      "firefox@developer-edition"
      "floorp"
      # "vivaldi"       # Migrated to nix (Phase 5)
      "google-chrome@dev"
      # "tor-browser"   # Migrated to nix (Phase 5)
      
      # Media & Entertainment
      # "vlc"           # Migrated to nix (Phase 4)
      # "obs"           # Migrated to nix (Phase 4) - obs-studio
      # "musescore"     # Migrated to nix (Phase 5)
      # "mixxx"         # Migrated to nix (Phase 5)
      # "surge-xt"      # Migrated to nix (Phase 5) - surge-XT
      
      # Gaming & Emulation
      "steam"
      "epic-games"
      "minecraft"
      "retroarch-metal"
      # "prismlauncher" # Migrated to nix (Phase 5)
      "whisky"
      
      # Communication & Productivity
      # LINE available via MAS (already configured)
      # "discord"      # Could migrate to nix but keeping for macOS integration
      # "slack"        # Could migrate to nix but keeping for macOS integration
      # "thunderbird"   # Migrated to nix (Phase 4)
      # "obsidian"      # Migrated to nix (Phase 5)
      # "zotero"        # Migrated to nix (Phase 5)
      
      # Utilities & System
      # "bitwarden"     # Migrated to nix (Phase 5) - bitwarden-desktop
      # "espanso"       # Migrated to nix (Phase 5)
      "shortcat"
      "middleclick"
      "jordanbaird-ice"
      # "syncthing"     # Migrated to nix (Phase 5)
      # "spacedrive"    # Migrated to nix (Phase 5)
      # "rustdesk"      # Migrated to nix (Phase 5)
      # "wireshark"     # Migrated to nix (Phase 5)
      "cloudflare-warp"
      "vmware-fusion"
      
      # Office & Documents
      # "libreoffice"   # Migrated to nix (Phase 4)
      # "onlyoffice"    # Migrated to nix (Phase 5) - onlyoffice-bin
      "microsoft-excel"
      "microsoft-word"
      "microsoft-powerpoint"
      
      # AI & Assistant tools
      "claude"
      "chatgpt"
      # "ollama"        # Migrated to nix (Phase 5)
      
      # Fonts
      "font-hackgen-nerd"
      "font-udev-gothic-nf"
      "font-plemol-jp-nf"  # Correct name
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