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
    enable = false; # Disable for Determinate Nix
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
      "wezterm"
      "visual-studio-code"
      
      # Development & Programming
      "cursor"
      "zed"
      "figma"
      # "docker"        # Migrated to nix (Phase 4)
      "virtualbox"
      "podman-desktop"
      "unity-hub"
      "godot"
      "freecad"
      "kicad"
      "goxel"
      
      # Creative & Design
      # "gimp"          # Migrated to nix (Phase 4)
      # "krita"         # Migrated to nix (Phase 4)  
      # "inkscape"      # Migrated to nix (Phase 4)
      "scribus"
      "fontforge"
      "material-maker"
      "natron"
      "opentoonz"
      
      # Browsers
      "zen"
      "firefox@developer-edition"
      "floorp"
      "vivaldi"
      "google-chrome@dev"
      "tor-browser"
      
      # Media & Entertainment
      # "vlc"           # Migrated to nix (Phase 4)
      # "obs"           # Migrated to nix (Phase 4) - obs-studio
      "musescore"
      "mixxx"
      "surge-xt"
      
      # Gaming & Emulation
      "steam"
      "epic-games"
      "minecraft"
      "retroarch-metal"
      "prismlauncher"
      "whisky"
      
      # Communication & Productivity
      # LINE available via MAS (already configured)
      "discord"
      "slack"
      # "thunderbird"   # Migrated to nix (Phase 4)
      "obsidian"
      "zotero"
      
      # Utilities & System
      "bitwarden"
      "espanso"
      "shortcat"
      "middleclick"
      "jordanbaird-ice"
      "syncthing"
      "spacedrive"
      "rustdesk"
      "wireshark"
      "cloudflare-warp"
      "vmware-fusion"
      
      # Office & Documents
      # "libreoffice"   # Migrated to nix (Phase 4)
      "onlyoffice"
      "microsoft-excel"
      "microsoft-word"
      "microsoft-powerpoint"
      
      # AI & Assistant tools
      "claude"
      "chatgpt"
      "ollama"
      
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