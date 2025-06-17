{ config, pkgs, username, homeDirectory, dotfilesDirectory, ... }:

{
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
    firefox          # Base Firefox browser
    thunderbird      # Email client
    
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
        
        # Trackpad tap behavior - allow left tap, disable right tap
        "com.apple.mouse.tapBehavior" = 1;  # Enable left tap, disable right tap behaviors
      };

      trackpad = {
        # 左タップクリックは有効、右タップクリックのみ無効化
        Clicking = true;  # Enable tap to click (primary left click)
        TrackpadRightClick = false;  # Disable right tap for right click
        TrackpadCornerSecondaryClick = 0;  # Disable corner secondary click
        
        # 有用な機能は維持
        TrackpadThreeFingerDrag = true;  # Keep three finger drag
        
        # 物理クリック関連（押し込みクリック）は有効のまま
        # 物理的な右クリック（Control+Click相当や押し込み）は機能する
        ActuationStrength = 1;  # Light physical click sensitivity
        ForceSuppressed = false;  # Enable Force Touch if available
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
      "epic-games"
      "whisky"
      "minecraft"
      
      # Office & Productivity
      "onlyoffice"
      "libreoffice"
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
      "davinci-resolve"
      "zrythm"
      
      # Browsers (special editions and macOS-optimized versions)
      "zen"
      "google-chrome@dev"
      "vivaldi"
      "floorp"
      "firefox@developer-edition"
      "tor-browser"
      # Note: Base firefox moved to nix for better performance
      
      # Communication & Social
      "discord"
      "slack"
      # "thunderbird" moved to nix
      
      # AI & Assistant tools (native apps)
      "claude"
      "chatgpt"
      "ollama"
      
      # Development Tools & Editors
      "visual-studio-code"
      "zed"
      "wezterm"
      
      # Research & Knowledge Management
      "obsidian"
      "zotero"
      
      # Media & Security
      "bitwarden"
      
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