# Core packages available across all platforms
{ lib, pkgs, platformInfo, ... }:

let
  # Base CLI tools that work everywhere
  corePackages = with pkgs; [
    # Essential shell tools
    coreutils
    findutils
    gnugrep
    gnused
    gawk
    
    # File operations
    file
    unzip
    gzip
    bzip2
    xz
    
    # Network tools
    curl
    wget
    
    # Development essentials
    git
    vim
    
    # Process management
    htop
    killall
    
    # Text processing
    jq
    
    # Archive tools
    gnutar
  ];

  # Modern CLI replacements (capability-aware)
  modernTools = with pkgs; lib.optionals (!((platformInfo.capabilities.limitedPackages or false) || (platformInfo.capabilities.limitedResources or false))) [
    # Modern replacements
    eza      # ls replacement
    bat      # cat replacement  
    fd       # find replacement
    ripgrep  # grep replacement
    fzf      # fuzzy finder
    zoxide   # cd replacement
    delta    # git diff tool
    
    # Shell history and experience
    atuin    # enhanced shell history with sync
    fastfetch # system info display (modern neofetch)
    
    # Development tools
    gh       # GitHub CLI
    lazygit  # Git TUI
    
    # System monitoring
    bottom   # top replacement
    procs    # ps replacement
    dust     # du replacement
    duf      # df replacement (disk usage)
    gdu      # enhanced du with TUI
    
    # File management
    yazi     # modern file manager
    
    # Terminal multiplexer
    tmux
    
    # Shell enhancement
    starship # prompt
    direnv   # environment management
  ];

  # Development languages and runtimes (capability-aware)
  devTools = with pkgs; lib.optionals (platformInfo.capabilities.supportsFullDevEnvironment or true) [
    # Python runtime only (packages managed via project shells to avoid conflicts)
    python3
    # Python packages will be managed via python3.withPackages in project-specific shells
    
    # Node.js runtime (Nix-managed)
    nodejs
    # Essential Node.js tools only (avoid LICENSE conflicts)
    nodePackages.npm
    nodePackages.yarn
    nodePackages.typescript-language-server
    # Other tools (typescript, eslint, prettier, etc.) managed via project shells
    
    # Go with common tools (complete Nix integration)
    go
    gopls           # Go language server
    golangci-lint   # Go linter
    # gotools removed due to bundle command conflict with Ruby
    
    # Rust with essential tools (complete Nix integration)
    rustc
    cargo
    rust-analyzer
    rustfmt
    clippy
    cargo-watch     # Auto-rebuild on file changes
    cargo-edit      # Cargo add/remove/upgrade commands
    
    # Ruby with essential tools (complete Nix integration)  
    ruby
    # bundler is included in Ruby, no separate package needed
    
    # PHP with essential tools (complete Nix integration)  
    php
    # composer conflicts with prettier LICENSE, will be managed via project shells
    
    # Java ecosystem (complete Nix integration)
    openjdk      # Java Development Kit
    # maven and gradle managed via project shells to avoid conflicts
    
    # Other language runtimes
    lua          # Lua programming language (migrated from Homebrew)
    luarocks     # Lua package manager (migrated from Homebrew)
    
    # Build tools
    gnumake
    cmake
    
    # Math libraries
    gmp          # GNU Multiple Precision Arithmetic Library (migrated from Homebrew)
    
    # AI Development Tools
    claude-code  # Anthropic Claude Code CLI (migrated from nodebrew)
    
    # Language servers (for editors)
    nil              # Nix LSP
    nodePackages.typescript-language-server
    gopls
    rust-analyzer
    lua-language-server  # Lua LSP for enhanced development
    
    # MCP Server packages (migrated from nodebrew)
    # Note: Some packages may need to be installed via npm if not available in nixpkgs
  ];

  # Platform-specific packages (enhanced detection)
  platformSpecific = 
    if (lib.hasPrefix "darwin" (platformInfo.platform or "unknown")) then with pkgs; [
      # macOS specific tools
      coreutils-prefixed  # GNU coreutils with g prefix
      mas                 # Mac App Store CLI
    ] ++ lib.optionals (platformInfo.optimizations.maxMemoryMB or 4096 > 8000) [
      # Apple Silicon optimized tools
    ] else if (platformInfo.platform or "unknown") == "android" then with pkgs; [
      # Android/Termux specific lightweight tools
      openssh
      rsync
      busybox  # Space-efficient utilities
    ] else if (platformInfo.platform or "unknown") == "wsl" then with pkgs; [
      # WSL specific tools
      openssh
      rsync
      wslu  # WSL utilities
    ] else if (platformInfo.platform or "unknown") == "nixos" then with pkgs; [
      # NixOS specific system tools
      openssh
      rsync
      systemd
    ] else with pkgs; [
      # Generic Linux tools
      openssh
      rsync
    ];

  # GUI applications (only where supported)
  guiApplications = with pkgs; lib.optionals (platformInfo.capabilities.hasGUI or false) [
    # Only install GUI apps where they're supported
  ];
  
  # Heavy development tools (resource-aware)
  heavyDevTools = with pkgs; lib.optionals (!(platformInfo.capabilities.limitedResources or false)) (
    [
      docker
      docker-compose
      # These are excluded on resource-limited platforms like Android
    ] ++ lib.optionals (!(platformInfo.isDarwin or false)) [
      # Linux-only tools
      kubernetes
    ]
  );

in {
  # Export package lists with intelligent filtering
  packages = 
    let 
      allPackages = corePackages ++ modernTools ++ devTools ++ platformSpecific ++ guiApplications ++ heavyDevTools;
      # Apply platform-specific filtering if available
      filtered = if (platformInfo.filterForPlatform or null) != null 
                 then platformInfo.filterForPlatform allPackages
                 else allPackages;
    in filtered;
  
  # Categorized for selective inclusion
  coreTools = corePackages;
  modernTools = modernTools;
  developmentTools = devTools;
  platformTools = platformSpecific;
  guiTools = guiApplications;
  heavyTools = heavyDevTools;
  
  # Platform capability summary for debugging
  platformSummary = 
    let 
      allPackages = corePackages ++ modernTools ++ devTools ++ platformSpecific ++ guiApplications ++ heavyDevTools;
      filtered = if (platformInfo.filterForPlatform or null) != null 
                 then platformInfo.filterForPlatform allPackages
                 else allPackages;
    in {
      platform = platformInfo.platform or "unknown";
      capabilities = platformInfo.capabilities or {};
      packageCount = builtins.length filtered;
    categories = {
      core = builtins.length corePackages;
      modern = builtins.length modernTools;
      development = builtins.length devTools;
      platform = builtins.length platformSpecific;
      gui = builtins.length guiApplications;
      heavy = builtins.length heavyDevTools;
    };
  };
}