{ config, lib, pkgs, username, homeDirectory, dotfilesDirectory, platformInfo, ... }:

{
  imports = [
    # ../../common/system/optimization.nix  # Temporarily disabled due to SpotlightServer config issues
    # ../../common/system/maintenance.nix  # Temporarily disabled due to dependency on optimization
  ];
  
  # System optimization temporarily disabled
  # dotfiles.system.optimization = {
  #   enable = true;
  #   nixBuildOptimization = true;
  #   macOSOptimization = true;
  #   performanceProfiles = "balanced";
  # };
  
  # System maintenance temporarily disabled
  # dotfiles.system.maintenance = {
  #   enable = true;
  #   autoGarbageCollection = true;
  #   autoOptimization = true;
  #   retentionDays = 30;
  # };

  # Automation and orchestration (temporarily disabled)
  # dotfiles.automation = {
  #   enable = true;
  #   profile = "standard";
  #   multiEnvironment = true;
  # };

  # Advanced development environment
  dotfiles.development = {
    enable = true;
    profile = "full";
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
  # Core packages imported above in main imports section

  # System-wide packages (Darwin-specific + GUI applications)
  environment.systemPackages = with pkgs; let
    # Simplified core packages (no platformInfo dependency)
    corePackages = [
      # Essential tools
      git vim curl wget jq htop
      # GNU tools
      coreutils gnugrep gnused gawk gnumake
      # Development (basic runtimes only, tools via home-manager)
      # python3 nodejs go rustc cargo lua managed via home-manager core packages
      # Modern CLI tools
      eza bat fd ripgrep fzf starship
    ];
    darwinSpecific = [
      # macOS specific tools
      mas  # Mac App Store CLI
      
      # Development utilities (macOS optimized)
      docker
      docker-compose
      
      # Secret management tools
      sops
      age
      
      # Network tools
      nss         # Network Security Services
      tcpdump     # Network packet analyzer
      bandwhich   # Network bandwidth monitor
      
      # Archive tools
      p7zip       # 7-Zip archive tool
      unar        # Archive extraction tool
      
      # Text processing
      yq          # YAML processor
      pandoc      # Document converter
      
      # Modern CLI replacements
      sd          # Modern sed replacement
      tokei       # Code statistics
      tealdeer    # Modern man pages (tldr)
      hyperfine   # Benchmarking tool
      
      # Terminal tools
      tmux        # Terminal multiplexer
      neovim      # Modern Vim editor
      
      # File operations
      rename      # Rename utility
      
      # GUI applications available in nixpkgs (better performance & reproducibility)
      # Note: Many GUI apps not available on macOS, managed via Homebrew instead
      # chromium - Not available on macOS ARM64
      # libreoffice - Available via Homebrew for better macOS integration
      # gimp - Available via Homebrew for better macOS integration
      # inkscape - Available via Homebrew for better macOS integration
      # vlc - Available via Homebrew for better macOS integration
      # obs-studio - Available via Homebrew for better macOS integration
      # discord - Available via Homebrew for better macOS integration
      # slack - Available via Homebrew for better macOS integration
      # vscode - Available via Homebrew for better macOS integration
    ];
  in corePackages ++ darwinSpecific;

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

  # System environment variables
  environment.variables = {
    USER = username;  # Ensure USER is set consistently
  };
  
  # Override launchd environment for home-manager
  launchd.user.envVariables = {
    USER = username;
  };
  
  # System activation script
  system.activationScripts.preActivation.text = ''
    export USER="${username}"
    export HOME="${homeDirectory}"
    echo "System activation: Setting USER to $USER, HOME to $HOME"
  '';

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
      "nikitabobko/tap"       # AeroSpace
      "felixkratz/formulae"   # sketchybar
    ];
    
    brews = [
      # Window management (requires Homebrew for proper macOS integration)
      "aerospace"
      "sketchybar"
      
      # Note: VoiceVox and Battery now managed as Homebrew casks below
      # Note: coreutils, gmp, lua, luarocks migrated to Nix for better reproducibility
    ];
    
    casks = [
      # Core productivity (macOS-specific tools only) 
      "raycast"
      "karabiner-elements"
      
      # Specialized tools (formerly in brews/taps)
      "voicevox"              # Text-to-speech synthesis
      "battery"               # Battery charge limiter for macOS
      
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
      "gimp"          # GNU Image Manipulation Program
      "krita"
      "blender"
      "scribus"
      "fontforge"
      "natron"
      "opentoonz"
      "darktable"     # Professional photo workflow
      "inkscape"      # Vector graphics editor
      
      # Media & Entertainment (macOS-specific versions only)
      "musescore"
      "mixxx" 
      "surge-xt"
      
      # Gaming & Emulation
      "steam"
      "retroarch-metal"
      "prismlauncher"
      "epic-games"
      "minecraft"
      
      # Office & Productivity (macOS-specific versions only)
      "libreoffice"   # Open source office suite
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
      
      # Cloud Storage & Sync
      "amazon-photos"         # Amazon Photos for cloud photo storage
      "google-drive"          # Google Drive for cloud file storage
      
      # Professional Tools
      # Note: DaVinci Resolve and Zrythm not available in Homebrew casks
      
      # Browsers (special editions and macOS-optimized versions)
      "zen"
      "google-chrome@dev"
      "vivaldi"
      "floorp"
      "tor-browser"
      # Note: Firefox and Thunderbird not managed by dotfiles
      
      # Communication & Social (native macOS apps only)
      # Note: discord, slack moved to Nix for better integration
      
      # AI & Assistant tools (native apps)
      "ollama"
      
      # Development Tools & Editors (macOS-specific versions only)
      "visual-studio-code"  # Microsoft Visual Studio Code
      "zed"
      "wezterm"
      
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