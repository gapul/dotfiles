{ config, pkgs, username, homeDirectory, dotfilesDirectory, ... }:

{
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
        
        # Trackpad tap behavior - disable all tap clicking, keep physical click only
        "com.apple.mouse.tapBehavior" = 0;  # Disable all tap behaviors
        "com.apple.trackpad.enableSecondaryClick" = true;  # Enable secondary click for physical press
        "com.apple.AppleMultitouchTrackpad.Clicking" = false;  # Disable trackpad clicking via tap
        "com.apple.AppleMultitouchTrackpad.TrackpadRightClick" = true;  # Enable two-finger physical right click
      };

      trackpad = {
        # 全てのタップクリックを無効化、物理押し込みクリックのみ有効
        Clicking = false;  # Disable tap to click (all taps)
        TrackpadRightClick = true;  # Enable two-finger physical right click (not tap)
        TrackpadCornerSecondaryClick = 0;  # Disable corner secondary click
        
        # 有用なジェスチャーは維持
        TrackpadThreeFingerDrag = true;  # Keep three finger drag
        
        # 物理クリック関連（押し込みクリック）は有効のまま
        # 1本指物理クリック = 左クリック、2本指物理クリック = 右クリック
        ActuationStrength = 1;  # Light physical click sensitivity
        ForceSuppressed = false;  # Enable Force Touch if available
        
        # タップジェスチャーは無効化（物理クリックは除く）
        TrackpadTwoFingerDoubleTapGesture = 0;  # Disable two finger double tap
        TrackpadOneFingerDoubleTapGesture = 0;  # Disable one finger double tap
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
      "Pages" = 409201541;
      "Numbers" = 409203825;
      "Keynote" = 409183694;
      "Xcode" = 497799835;
      "TestFlight" = 899247664;
      "Logic Pro" = 634148309;
      "Final Cut Pro" = 424389933;
      "Motion" = 434290957;
      "Compressor" = 424390742;
      "MainStage" = 634159523;
      "Transloader" = 1447648031;
      "Day One" = 1055511498;
      "Bear" = 1091189122;
      "Taska for GitHub-GitLab Issues" = 1490804956;
      "System Preferences" = 1564271834;
      "Finder" = 1042394095;
      "Safari" = 1146562112;
      "Amphetamine" = 937984704;
      "The Unarchiver" = 425424353;
      "MoneyMoney" = 872698314;
      "1Blocker- Ad Blocker & Privacy" = 1365531024;
    };
  };
}