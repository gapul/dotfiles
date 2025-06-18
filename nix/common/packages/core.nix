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

  # Modern CLI replacements (when available)
  modernTools = with pkgs; lib.optionals (!(platformInfo.capabilities.limitedPackages or false)) [
    # Modern replacements
    eza      # ls replacement
    bat      # cat replacement  
    fd       # find replacement
    ripgrep  # grep replacement
    fzf      # fuzzy finder
    zoxide   # cd replacement
    delta    # git diff tool
    
    # Development tools
    gh       # GitHub CLI
    lazygit  # Git TUI
    
    # System monitoring
    bottom   # top replacement
    procs    # ps replacement
    dust     # du replacement
    
    # Terminal multiplexer
    tmux
    
    # Shell enhancement
    starship # prompt
    direnv   # environment management
  ];

  # Development languages and runtimes
  devTools = with pkgs; lib.optionals (platformInfo.capabilities.canInstallPackages or true) [
    # Language runtimes
    python3
    nodejs
    go
    rustc
    cargo
    lua          # Lua programming language (migrated from Homebrew)
    luarocks     # Lua package manager (migrated from Homebrew)
    
    # Build tools
    gnumake
    cmake
    
    # Math libraries
    gmp          # GNU Multiple Precision Arithmetic Library (migrated from Homebrew)
    
    # Language servers (for editors)
    nil              # Nix LSP
    python3Packages.python-lsp-server
    nodePackages.typescript-language-server
    gopls
    rust-analyzer
    lua-language-server  # Lua LSP for enhanced development
  ];

  # Platform-specific core packages
  platformSpecific = 
    if (platformInfo.platform or "unknown") == "darwin" then with pkgs; [
      # macOS specific tools
      coreutils-prefixed  # GNU coreutils with g prefix
      
    ] else if (platformInfo.platform or "unknown") == "android" then with pkgs; [
      # Android/Termux specific
      openssh
      
    ] else with pkgs; [
      # Linux/WSL specific
      openssh
      rsync
    ];

in {
  # Export package lists
  packages = (platformInfo.filterForPlatform or (x: x)) (
    corePackages ++ 
    modernTools ++ 
    devTools ++ 
    platformSpecific
  );
  
  # Categorized for selective inclusion
  core = corePackages;
  modern = modernTools;
  development = devTools;
  platform = platformSpecific;
}