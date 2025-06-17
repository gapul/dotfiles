# Linux Server Configuration (headless)
{ config, lib, pkgs, platformInfo, ... }:

{
  # Server-focused packages (no GUI)
  home.packages = with pkgs; platformInfo.filterForPlatform [
    # Server administration
    openssh
    rsync
    screen
    tmux
    
    # Network tools
    netcat
    socat
    nmap
    tcpdump
    iftop
    iotop
    nethogs
    
    # System monitoring
    htop
    btop
    bottom
    iotop
    
    # File operations
    unzip
    p7zip
    rsync
    
    # Development tools
    git
    vim
    nano
    
    # Database tools
    postgresql
    sqlite
    redis
    
    # Web tools
    curl
    wget
    httpie
    
    # Container tools
    docker
    docker-compose
    podman
    
    # System utilities
    procps
    psmisc
    lsof
    tree
    
    # Archive and compression
    gzip
    bzip2
    xz
    tar
    
    # Text processing
    jq
    yq-go
    
    # Performance tools
    perf-tools
    strace
    
    # Backup tools
    borgbackup
    rclone
  ];

  # Server-specific services
  services = lib.mkIf platformInfo.capabilities.canManageServices {
    # SSH agent for server management
    ssh-agent.enable = true;
    
    # GPG agent for signing
    gpg-agent = {
      enable = true;
      enableSshSupport = true;
      pinentryPackage = pkgs.pinentry-curses;  # CLI-only
    };
    
    # System monitoring (if systemd available)
    systemd.user.services = lib.mkIf platformInfo.capabilities.hasSystemd {
      # Log monitoring
      log-monitor = {
        Unit = {
          Description = "System Log Monitor";
          After = [ "multi-user.target" ];
        };
        Service = {
          Type = "simple";
          ExecStart = "${pkgs.writeShellScript "log-monitor" ''
            #!/bin/bash
            # Simple log monitoring for servers
            journalctl -f --priority=err
          ''}";
          Restart = "always";
          RestartSec = 5;
        };
        Install.WantedBy = [ "default.target" ];
      };
    };
  };

  # Server environment variables
  home.sessionVariables = {
    # Server identification
    SERVER_MODE = "1";
    NO_GUI = "1";
    
    # Editor for server use
    EDITOR = "vim";
    VISUAL = "vim";
    PAGER = "less";
    
    # Performance settings
    HISTSIZE = "10000";
    HISTFILESIZE = "20000";
    
    # Network settings
    CURL_CA_BUNDLE = "/etc/ssl/certs/ca-certificates.crt";
    
    # Container settings
    DOCKER_BUILDKIT = "1";
    COMPOSE_DOCKER_CLI_BUILD = "1";
  };

  # Server-specific shell configuration
  programs.zsh.initExtra = lib.mkAfter ''
    # Server-specific shell setup
    
    # Enhanced command history for server management
    setopt EXTENDED_HISTORY
    setopt INC_APPEND_HISTORY
    setopt SHARE_HISTORY
    setopt HIST_VERIFY
    setopt HIST_IGNORE_ALL_DUPS
    
    # Server administration functions
    function sys-info() {
      echo "=== System Information ==="
      echo "Hostname: $(hostname)"
      echo "Uptime: $(uptime)"
      echo "Load: $(cat /proc/loadavg)"
      echo "Memory: $(free -h | grep Mem)"
      echo "Disk: $(df -h / | tail -1)"
      echo "Network: $(ip route get 1 | head -1 | cut -d' ' -f7)"
    }
    
    function disk-usage() {
      echo "=== Disk Usage ==="
      df -h
      echo ""
      echo "=== Largest directories ==="
      du -sh /* 2>/dev/null | sort -hr | head -10
    }
    
    function proc-top() {
      echo "=== Top Processes ==="
      ps aux --sort=-%cpu | head -10
      echo ""
      echo "=== Memory Usage ==="
      ps aux --sort=-%mem | head -10
    }
    
    function net-info() {
      echo "=== Network Information ==="
      ip addr show
      echo ""
      echo "=== Active Connections ==="
      ss -tuln
    }
    
    function log-errors() {
      echo "=== Recent Errors ==="
      journalctl --priority=err --since="1 hour ago" --no-pager
    }
    
    function quick-backup() {
      local backup_dir="/tmp/quick-backup-$(date +%Y%m%d_%H%M%S)"
      mkdir -p "$backup_dir"
      
      echo "Creating quick backup in $backup_dir..."
      
      # Backup common configuration files
      cp -r ~/.ssh "$backup_dir/" 2>/dev/null || true
      cp -r ~/.config "$backup_dir/" 2>/dev/null || true
      cp ~/.bashrc ~/.zshrc ~/.profile "$backup_dir/" 2>/dev/null || true
      
      # Backup crontabs
      crontab -l > "$backup_dir/crontab.txt" 2>/dev/null || true
      
      echo "Quick backup completed: $backup_dir"
    }
    
    # Docker management functions
    if command -v docker >/dev/null 2>&1; then
      function docker-cleanup() {
        echo "Cleaning up Docker..."
        docker system prune -f
        docker volume prune -f
        docker image prune -f
      }
      
      function docker-status() {
        echo "=== Docker Status ==="
        docker version --format 'Version: {{.Server.Version}}'
        echo "Running containers: $(docker ps -q | wc -l)"
        echo "Total containers: $(docker ps -a -q | wc -l)"
        echo "Images: $(docker images -q | wc -l)"
        echo "Volumes: $(docker volume ls -q | wc -l)"
        echo ""
        echo "=== Resource Usage ==="
        docker system df
      }
    fi
    
    # Service management aliases
    if command -v systemctl >/dev/null 2>&1; then
      alias svc-status="systemctl status"
      alias svc-start="sudo systemctl start"
      alias svc-stop="sudo systemctl stop"
      alias svc-restart="sudo systemctl restart"
      alias svc-enable="sudo systemctl enable"
      alias svc-disable="sudo systemctl disable"
      alias svc-list="systemctl list-units --type=service"
      alias svc-failed="systemctl --failed"
    fi
    
    # Log viewing aliases
    alias logs="journalctl -f"
    alias logs-error="journalctl --priority=err"
    alias logs-boot="journalctl -b"
    alias logs-kernel="journalctl -k"
    
    # Quick system monitoring
    alias cpu="top -o %CPU"
    alias mem="top -o %MEM"
    alias ports="ss -tuln"
    alias connections="ss -tup"
    
    # File permission helpers
    alias fix-perms="find . -type f -exec chmod 644 {} \; && find . -type d -exec chmod 755 {} \;"
    alias web-perms="find . -type f -exec chmod 644 {} \; && find . -type d -exec chmod 755 {} \; && chmod +x *.sh *.py"
  '';

  # Git configuration for server use
  programs.git = {
    enable = true;
    extraConfig = {
      # Server-specific git settings
      core = {
        editor = "vim";
        pager = "less -R";
      };
      
      # Security for server use
      receive = {
        denyNonFastForwards = true;
      };
      
      # Performance optimizations
      gc = {
        auto = 1000;
      };
      
      # Remote repository settings
      remote = {
        origin = {
          prune = true;
        };
      };
    };
  };

  # SSH configuration for server management
  programs.ssh = {
    enable = true;
    
    # Server-focused SSH config
    extraConfig = ''
      # Server management SSH settings
      
      # Security settings
      StrictHostKeyChecking ask
      VerifyHostKeyDNS yes
      
      # Performance settings
      ControlMaster auto
      ControlPath ~/.ssh/master-%r@%h:%p
      ControlPersist 600
      
      # Compression for slow connections
      Compression yes
      
      # Keep connections alive
      ServerAliveInterval 60
      ServerAliveCountMax 3
      
      # Forward agent for deployments
      ForwardAgent yes
      
      # Common server patterns
      Host *.local
        StrictHostKeyChecking no
        UserKnownHostsFile /dev/null
        LogLevel QUIET
      
      Host prod-*
        ForwardAgent no
        StrictHostKeyChecking yes
      
      Host staging-*
        ForwardAgent yes
        StrictHostKeyChecking ask
    '';
  };

  # Tmux configuration for server sessions
  programs.tmux = lib.mkIf (lib.elem pkgs.tmux config.home.packages) {
    enable = true;
    
    # Server-optimized tmux settings
    extraConfig = ''
      # Server tmux configuration
      
      # Status bar for server monitoring
      set -g status-interval 5
      set -g status-left-length 30
      set -g status-right-length 60
      
      set -g status-left '#[fg=green]#H#[default] '
      set -g status-right '#[fg=yellow]Load: #(cat /proc/loadavg | cut -d" " -f1-3)#[default] #[fg=cyan]%Y-%m-%d %H:%M#[default]'
      
      # Server session management
      bind-key S command-prompt -p "Session name:" "new-session -s '%%'"
      bind-key L list-sessions
      
      # Easy pane navigation for server management
      bind-key h select-pane -L
      bind-key j select-pane -D
      bind-key k select-pane -U
      bind-key l select-pane -R
      
      # Quick layouts for server monitoring
      bind-key M-1 select-layout even-horizontal
      bind-key M-2 select-layout even-vertical
      bind-key M-3 select-layout main-horizontal
      bind-key M-4 select-layout main-vertical
      
      # Logging for server sessions
      bind-key P pipe-pane -o "cat >>~/tmux-session-#S-#I-#P.log" \; display "Logging toggled"
    '';
  };

  # Minimal dotfiles for server use
  home.file = {
    # Server monitoring scripts
    ".local/bin/server-monitor".text = ''
      #!/bin/bash
      # Simple server monitoring script
      
      echo "=== Server Monitor - $(date) ==="
      echo ""
      
      # System overview
      echo "System Load:"
      uptime
      echo ""
      
      echo "Memory Usage:"
      free -h
      echo ""
      
      echo "Disk Usage:"
      df -h /
      echo ""
      
      echo "Network Connections:"
      ss -tuln | wc -l
      echo " active connections"
      echo ""
      
      # Service status (if systemd)
      if command -v systemctl >/dev/null 2>&1; then
        echo "Failed Services:"
        systemctl --failed --no-legend --no-pager | wc -l
        echo " failed services"
        echo ""
      fi
      
      # Recent errors
      echo "Recent Errors (last hour):"
      journalctl --priority=err --since="1 hour ago" --no-pager -q | wc -l
      echo " error messages"
    '';
    
    # Server maintenance script
    ".local/bin/server-maintenance".text = ''
      #!/bin/bash
      # Server maintenance script
      
      echo "=== Server Maintenance - $(date) ==="
      
      # System updates (if applicable)
      echo "Checking for system updates..."
      if command -v apt >/dev/null 2>&1; then
        sudo apt update && sudo apt list --upgradable
      elif command -v dnf >/dev/null 2>&1; then
        sudo dnf check-update
      elif command -v nixos-rebuild >/dev/null 2>&1; then
        echo "NixOS system - use 'nixos-rebuild switch' to update"
      fi
      
      # Log rotation
      echo "Cleaning old logs..."
      journalctl --vacuum-time=30d >/dev/null 2>&1 || true
      
      # Temporary file cleanup
      echo "Cleaning temporary files..."
      find /tmp -type f -atime +7 -delete 2>/dev/null || true
      
      # Docker cleanup (if available)
      if command -v docker >/dev/null 2>&1; then
        echo "Cleaning Docker resources..."
        docker system prune -f >/dev/null 2>&1 || true
      fi
      
      echo "Maintenance completed!"
    '';
  };

  # Make scripts executable
  home.activation.serverScripts = lib.hm.dag.entryAfter ["writeBoundary"] ''
    chmod +x "${config.home.homeDirectory}/.local/bin/server-monitor"
    chmod +x "${config.home.homeDirectory}/.local/bin/server-maintenance"
  '';
}