{ pkgs }:

# Development tools and language environments
with pkgs; [
  # Version control
  git
  gh
  git-lfs
  
  # Text editors and IDEs
  neovim
  # vscode  # May keep in darwin.nix homebrew section during transition
  # zed     # Check nixpkgs availability
  
  # Shell and terminal tools
  tmux
  starship
  zsh
  
  # Code formatting and linting
  shellcheck
  nixpkgs-fmt
  
  # Build tools
  gnumake
  cmake
  pkg-config
  
  # Language runtimes - Python
  python312
  python312Packages.pip
  python312Packages.virtualenv
  python312Packages.setuptools
  python312Packages.wheel
  
  # Language runtimes - Node.js
  nodejs_20
  nodePackages.npm
  nodePackages.yarn
  nodePackages.pnpm
  
  # Language runtimes - Rust
  rustc
  cargo
  rust-analyzer
  rustfmt
  clippy
  
  # Language runtimes - Go
  go
  gopls  # Go language server
  
  # Database tools
  sqlite
  # mysql80  # May need specific version
  
  # Container tools
  # docker    # Keep in Homebrew during transition
  # podman    # Alternative container runtime
  
  # Cloud and infrastructure
  # terraform
  # kubectl
  
  # API and web development
  curl
  wget
  jq
  yq  # YAML processor
  httpie
  
  # Documentation tools
  pandoc
  # mdbook  # For Rust-style documentation
  
  # Performance and debugging
  htop
  btop
  iotop
  nmap
  
  # File processing
  fd
  ripgrep
  bat
  eza
  tree
  unzip
  gzip
  rsync
  
  # Modern CLI replacements
  zoxide  # Smart cd
  fzf     # Fuzzy finder
  delta   # Git diff viewer
  
  # Development utilities
  direnv
  just    # Command runner
  watchman  # File watching
  
  # Network tools
  speedtest-cli
  bandwhich  # Network utilization
  
  # JSON/YAML tools
  jless   # JSON viewer
  
  # Benchmarking
  hyperfine  # Command-line benchmarking
]