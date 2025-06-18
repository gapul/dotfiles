{ pkgs }:

# System utilities and macOS-specific tools
with pkgs; [
  # Core system utilities
  coreutils
  findutils
  gnu-sed
  gnutar
  gawk
  gnugrep
  
  # File and directory tools
  tree
  fd
  ripgrep
  bat
  eza
  
  # Archive tools
  unzip
  gzip
  p7zip
  
  # Network utilities
  curl
  wget
  nmap
  speedtest-cli
  
  # System monitoring
  htop
  btop
  iotop
  
  # Process management
  pstree
  killall
  
  # Disk utilities
  ncdu  # Disk usage analyzer
  duf   # Modern df
  
  # System information
  neofetch
  
  # Terminal multiplexer
  tmux
  
  # Shell enhancements
  starship
  zoxide
  fzf
  
  # Mac App Store CLI
  mas
  
  # File synchronization
  rsync
  
  # Text processing
  jq
  yq
  
  # Clipboard utilities (macOS)
  # pbcopy/pbpaste are built-in on macOS
  
  # Font management
  fontconfig
  
  # Development utilities that are system-wide
  direnv
  
  # Security tools
  gnupg
  
  # Backup utilities
  # borgbackup
  # restic
  
  # System cleanup
  # bleachbit  # Check availability on macOS
  
  # Network debugging
  # wireshark  # GUI app, may keep in Homebrew
  
  # Performance monitoring
  # iftop      # Network monitoring
  # nethogs    # Per-process network monitoring
  
  # Virtualization utilities
  # qemu       # If needed for development
  
  # Remote access
  openssh
  
  # Time utilities
  # chrony     # May not be needed on macOS
  
  # Log analysis
  # logrotate  # May not be relevant for macOS
  
  # System backup
  # timeshift  # Linux-specific, macOS has Time Machine
]