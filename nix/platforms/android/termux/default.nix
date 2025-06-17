# Android/Termux Configuration via nix-on-droid
{ config, lib, pkgs, platformInfo, ... }:

{
  # Android-specific packages (heavily limited)
  home.packages = with pkgs; platformInfo.filterForPlatform [
    # Essential tools that work on Android
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
    
    # Network (limited)
    curl
    
    # Development essentials
    git
    vim
    
    # Text processing
    jq
    
    # Shell tools
    tmux
    
    # Development languages (if available)
    python3
    nodejs
    
    # Termux-specific tools
    openssh
    rsync
    
    # Archive tools
    tar
  ];

  # Android-specific shell configuration
  programs.zsh.initExtra = lib.mkAfter ''
    # Android/Termux specific environment setup
    
    # Termux environment
    if [[ -n "$PREFIX" ]]; then
      export ANDROID_ROOT="/system"
      export ANDROID_DATA="/data"
      export TERMUX_PREFIX="$PREFIX"
      
      # Add Termux paths
      export PATH="$PREFIX/bin:$PREFIX/libexec:$PATH"
      
      # Android-specific aliases
      alias termux-setup="pkg update && pkg upgrade"
      alias termux-info="termux-info"
      alias storage-setup="termux-setup-storage"
      
      # Storage access shortcuts
      if [[ -d "/data/data/com.termux/files/home/storage" ]]; then
        alias shared="cd /data/data/com.termux/files/home/storage/shared"
        alias downloads="cd /data/data/com.termux/files/home/storage/downloads"
        alias dcim="cd /data/data/com.termux/files/home/storage/dcim"
        alias pictures="cd /data/data/com.termux/files/home/storage/pictures"
        alias music="cd /data/data/com.termux/files/home/storage/music"
        alias movies="cd /data/data/com.termux/files/home/storage/movies"
      fi
      
      # Android development shortcuts
      alias logcat="logcat"
      alias adb-connect="adb connect localhost:5555"
      
      # Backup functions
      function backup-termux() {
        tar -czf "/data/data/com.termux/files/home/storage/downloads/termux-backup-$(date +%Y%m%d).tar.gz" \
          --exclude=".cache" \
          --exclude=".local/share/Trash" \
          -C /data/data/com.termux/files/home .
        echo "Backup saved to downloads/termux-backup-$(date +%Y%m%d).tar.gz"
      }
      
      # Limited package management
      alias pkg-search="pkg search"
      alias pkg-install="pkg install"
      alias pkg-remove="pkg uninstall"
      alias pkg-list="pkg list-installed"
    fi
    
    # Android-specific networking (often limited)
    if command -v termux-wifi-connectioninfo >/dev/null 2>&1; then
      alias wifi-info="termux-wifi-connectioninfo"
    fi
    
    # Battery and system info
    if command -v termux-battery-status >/dev/null 2>&1; then
      alias battery="termux-battery-status"
      alias sys-info="echo 'Battery:'; termux-battery-status; echo; echo 'WiFi:'; termux-wifi-connectioninfo 2>/dev/null || echo 'Not available'"
    fi
    
    # Clipboard integration (if available)
    if command -v termux-clipboard-set >/dev/null 2>&1; then
      alias copy="termux-clipboard-set"
      alias paste="termux-clipboard-get"
    fi
    
    # Camera access (if permissions granted)
    if command -v termux-camera-photo >/dev/null 2>&1; then
      alias photo="termux-camera-photo"
    fi
    
    # Wake lock functions
    if command -v termux-wake-lock >/dev/null 2>&1; then
      alias wake-lock="termux-wake-lock"
      alias wake-unlock="termux-wake-unlock"
    fi
  '';

  # Minimal Git configuration for Android
  programs.git = lib.mkIf (lib.elem pkgs.git config.home.packages) {
    enable = true;
    extraConfig = {
      # Android-specific git settings
      core = {
        editor = "vim";
        pager = "less";
        # Android filesystem is often case-insensitive
        ignorecase = true;
      };
      
      # Simple credential storage
      credential = {
        helper = "store";
      };
      
      # Basic settings
      init = {
        defaultBranch = "main";
      };
      
      pull = {
        rebase = true;
      };
    };
  };

  # SSH configuration for Android
  programs.ssh = lib.mkIf (lib.elem pkgs.openssh config.home.packages) {
    enable = true;
    
    extraConfig = ''
      # Android-specific SSH settings
      
      # Use simple authentication
      PasswordAuthentication yes
      PubkeyAuthentication yes
      
      # Android-specific key locations
      IdentityFile ~/.ssh/id_rsa
      IdentityFile ~/.ssh/id_ed25519
      
      # Connection settings optimized for mobile
      ServerAliveInterval 60
      ServerAliveCountMax 3
      TCPKeepAlive yes
      
      # Compression for mobile networks
      Compression yes
    '';
  };

  # Android session variables
  home.sessionVariables = {
    # Android identification
    ANDROID_DEVICE = "1";
    TERMUX_APP = "1";
    
    # Mobile-optimized settings
    EDITOR = "vim";
    PAGER = "less";
    BROWSER = "termux-open-url";
    
    # Termux paths
    TMPDIR = "\${PREFIX}/tmp";
    
    # Limited resources
    NO_GUI = "1";
    LIMITED_RESOURCES = "1";
    
    # Android-specific paths
    ANDROID_HOME = "/data/data/com.termux/files/home";
    
    # Python settings for Android
    PYTHONUNBUFFERED = "1";
    
    # Node.js settings
    NODE_ENV = "development";
  };

  # XDG directories for Android
  xdg = {
    enable = true;
    
    # Android-specific directories
    userDirs = {
      desktop = "${config.home.homeDirectory}";  # No desktop concept
      documents = "${config.home.homeDirectory}/storage/shared/Documents";
      download = "${config.home.homeDirectory}/storage/downloads";
      music = "${config.home.homeDirectory}/storage/music";
      pictures = "${config.home.homeDirectory}/storage/pictures";
      videos = "${config.home.homeDirectory}/storage/movies";
    };
  };

  # Minimal file associations for Android
  xdg.mimeApps.defaultApplications = {
    "text/plain" = [ "vim" ];
    "application/json" = [ "vim" ];
    "text/x-shellscript" = [ "vim" ];
    "text/x-python" = [ "vim" ];
    "text/html" = [ "termux-open-url" ];
    "x-scheme-handler/http" = [ "termux-open-url" ];
    "x-scheme-handler/https" = [ "termux-open-url" ];
  };

  # Android-specific configuration files
  home.file = {
    # Termux configuration
    ".termux/termux.properties".text = ''
      # Termux configuration for nix-on-droid
      
      # Use volume keys for extra keys
      extra-keys = [ \
        ['ESC', '|', '/', '~', 'UP', '$'], \
        ['TAB', 'CTRL', 'ALT', 'LEFT', 'DOWN', 'RIGHT'] \
      ]
      
      # Bell settings
      bell-character = ignore
      
      # Terminal settings
      terminal-margin-horizontal = 3
      terminal-margin-vertical = 3
      
      # Font size (adjust for device)
      fontsize = 12
      
      # Keyboard settings
      enforce-char-based-input = true
      hide-soft-keyboard-on-startup = false
    '';
    
    # Android-specific scripts
    ".local/bin/android-setup".text = ''
      #!/bin/bash
      # Android environment setup script
      
      echo "Setting up Android/Termux environment..."
      
      # Setup storage access
      if ! [[ -d "$HOME/storage" ]]; then
        echo "Setting up storage access..."
        termux-setup-storage
      fi
      
      # Install essential packages via pkg
      echo "Installing essential packages..."
      pkg update
      pkg install -y git curl wget openssh python nodejs
      
      # Setup SSH keys
      if ! [[ -f "$HOME/.ssh/id_ed25519" ]]; then
        echo "Generating SSH key..."
        ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N ""
        echo "SSH public key:"
        cat "$HOME/.ssh/id_ed25519.pub"
      fi
      
      # Setup dotfiles
      if ! [[ -d "$HOME/dotfiles" ]]; then
        echo "Cloning dotfiles..."
        git clone https://github.com/your-username/dotfiles.git "$HOME/dotfiles"
        cd "$HOME/dotfiles"
        
        # Activate nix-on-droid configuration
        if command -v nix-on-droid >/dev/null 2>&1; then
          nix-on-droid switch --flake .#android
        fi
      fi
      
      echo "Android setup complete!"
      echo "You may need to restart Termux for all changes to take effect."
    '';
  };

  # Make the setup script executable
  home.activation.androidSetup = lib.hm.dag.entryAfter ["writeBoundary"] ''
    chmod +x "${config.home.homeDirectory}/.local/bin/android-setup"
  '';
}