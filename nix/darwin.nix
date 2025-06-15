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
    
    # Window management (Phase 3 migration targets)
    # yabai     # To be migrated from Homebrew
    # skhd      # To be migrated from Homebrew
    # sketchybar # To be migrated from Homebrew
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
      # Moving to nixpkgs in Phase 3
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
      "docker"
      "virtualbox"
      "podman-desktop"
      "unity-hub"
      "godot"
      "freecad"
      "kicad"
      "goxel"
      
      # Creative & Design
      "gimp"
      "krita"
      "inkscape"
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
      "vlc"
      "obs"
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
      "thunderbird"
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
      "libreoffice"
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