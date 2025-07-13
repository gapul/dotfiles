# WSL Integration Configuration
{ config, lib, pkgs, platformInfo, ... }:

{
  # WSL-specific packages (no GUI, Windows integration focus)
  home.packages = with pkgs; [
    # Essential command line tools
    openssh
    rsync
    
    # Development tools
    git
    gh
    
    # Windows integration tools
    wslu  # WSL utilities
    
    # Network tools
    netcat
    socat
    
    # Archive tools
    unzip
    p7zip
    
    # Text editors
    vim
    nano
    
    # System tools
    procps
    psmisc
    lsof
    
    # File synchronization
    rclone
    
    # Database clients
    postgresql
    sqlite
    
    # Language runtimes for development
    python3
    nodejs
    go
    rustc
    cargo
  ];

  # WSL-specific shell configuration
  programs.zsh.initContent = lib.mkAfter ''
    # WSL-specific environment setup
    
    # Windows path integration
    if [[ -d "/mnt/c/Windows" ]]; then
      export WINDOWS_HOME="/mnt/c/Users/$USER"
      export PATH="$PATH:/mnt/c/Windows/System32:/mnt/c/Windows/System32/WindowsPowerShell/v1.0"
    fi
    
    # WSL utilities aliases
    if command -v wslpath >/dev/null 2>&1; then
      alias winpath="wslpath -w"
      alias linuxpath="wslpath -u"
    fi
    
    # Quick access to Windows directories
    alias windesk="cd $(wslpath -u $(cmd.exe /c 'echo %USERPROFILE%\Desktop' 2>/dev/null | tr -d '\r'))"
    alias windocs="cd $(wslpath -u $(cmd.exe /c 'echo %USERPROFILE%\Documents' 2>/dev/null | tr -d '\r'))"
    alias windown="cd $(wslpath -u $(cmd.exe /c 'echo %USERPROFILE%\Downloads' 2>/dev/null | tr -d '\r'))"
    
    # Windows app integration
    alias explorer="explorer.exe"
    alias notepad="notepad.exe"
    alias powershell="powershell.exe"
    alias cmd="cmd.exe"
    
    # Git credential manager integration
    if [[ -f "/mnt/c/Program Files/Git/mingw64/bin/git-credential-manager.exe" ]]; then
      export GIT_CREDENTIAL_HELPER="/mnt/c/Program Files/Git/mingw64/bin/git-credential-manager.exe"
      git config --global credential.helper "$GIT_CREDENTIAL_HELPER"
    fi
    
    # VS Code integration
    if command -v code.cmd >/dev/null 2>&1; then
      alias code="code.cmd"
    fi
    
    # Docker Desktop integration (if available)
    if [[ -S "/var/run/docker.sock" ]]; then
      export DOCKER_HOST="unix:///var/run/docker.sock"
    fi
  '';

  # Git configuration for WSL
  programs.git = {
    enable = true;
    extraConfig = {
      # WSL-specific git settings
      core = {
        autocrlf = "input";  # Handle Windows line endings
        filemode = false;    # Windows doesn't have executable bit
      };
      
      # Credential manager
      credential = {
        helper = "manager";
      };
      
      # Better performance on Windows filesystems
      preloadindex = true;
      fscache = true;
    };
  };

  # SSH configuration for WSL
  programs.ssh = {
    enable = true;
    
    # WSL-specific SSH config
    extraConfig = ''
      # Use Windows SSH agent if available
      Include ~/.ssh/config.d/windows-integration
      
      # WSL-specific settings
      IdentityAgent ~/.ssh/ssh-agent.sock
      
      # Performance optimization for Windows filesystem
      ControlMaster auto
      ControlPath ~/.ssh/master-%r@%h:%p
      ControlPersist 600
    '';
  };

  # Session variables for WSL
  home.sessionVariables = {
    # WSL identification
    WSL_DISTRO_NAME = "NixOS";
    
    # Browser for opening links
    BROWSER = "/mnt/c/Program Files/Mozilla Firefox/firefox.exe";
    
    # Windows integration
    WSLENV = "PATH/l:HOME/l:USERPROFILE/pu";
    
    # Display for X11 forwarding (if X server running on Windows)
    DISPLAY = ":0.0";
    
    # Libgl for OpenGL applications
    LIBGL_ALWAYS_INDIRECT = "1";
    
    # No GUI applications
    NO_GUI = "1";
  };

  # XDG directories setup for WSL
  xdg = {
    enable = true;
    
    # Use Windows directories when possible
    userDirs = let
      windowsHome = "/mnt/c/Users/${config.home.username}";
    in lib.mkIf (builtins.pathExists windowsHome) {
      desktop = "${windowsHome}/Desktop";
      documents = "${windowsHome}/Documents";
      download = "${windowsHome}/Downloads";
      music = "${windowsHome}/Music";
      pictures = "${windowsHome}/Pictures";
      videos = "${windowsHome}/Videos";
    };
  };

  # WSL-specific systemd services (if available)
  systemd.user.services = lib.mkIf platformInfo.capabilities.hasSystemd {
    # SSH agent
    ssh-agent = {
      Unit = {
        Description = "SSH Agent";
        Documentation = "man:ssh-agent(1)";
      };
      Service = {
        Type = "simple";
        Environment = "SSH_AUTH_SOCK=%i/ssh-agent.socket";
        ExecStart = "${pkgs.openssh}/bin/ssh-agent -D -a $SSH_AUTH_SOCK";
        ExecStartPost = "${pkgs.coreutils}/bin/systemctl --user set-environment SSH_AUTH_SOCK=$SSH_AUTH_SOCK";
      };
      Install.WantedBy = [ "default.target" ];
    };
    
    # Windows clipboard integration
    win-clipboard-sync = {
      Unit = {
        Description = "Windows Clipboard Sync";
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.writeShellScript "clipboard-sync" ''
          #!/bin/bash
          while true; do
            if command -v clip.exe >/dev/null 2>&1 && command -v powershell.exe >/dev/null 2>&1; then
              # Sync clipboard from Windows to Linux
              powershell.exe -Command "Get-Clipboard" 2>/dev/null | head -c -1 > /tmp/win-clipboard
              
              # Basic synchronization (can be enhanced)
              sleep 1
            fi
          done
        ''}";
        Restart = "always";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };

  # File associations for WSL (open with Windows apps)
  xdg.mimeApps.defaultApplications = lib.mkIf (lib.pathExists "/mnt/c/Windows") {
    "text/html" = [ "firefox-windows.desktop" ];
    "x-scheme-handler/http" = [ "firefox-windows.desktop" ];
    "x-scheme-handler/https" = [ "firefox-windows.desktop" ];
    "application/pdf" = [ "edge-windows.desktop" ];
    "text/plain" = [ "vscode-windows.desktop" ];
    "application/json" = [ "vscode-windows.desktop" ];
    "inode/directory" = [ "explorer-windows.desktop" ];
  };

  # Desktop entries for Windows applications
  xdg.desktopEntries = lib.mkIf (lib.pathExists "/mnt/c/Windows") {
    firefox-windows = {
      name = "Firefox (Windows)";
      comment = "Open Firefox in Windows";
      exec = "/mnt/c/Program Files/Mozilla Firefox/firefox.exe %U";
      mimeType = [ "text/html" "x-scheme-handler/http" "x-scheme-handler/https" ];
      categories = [ "Network" "WebBrowser" ];
    };
    
    vscode-windows = {
      name = "Visual Studio Code (Windows)";
      comment = "Open VS Code in Windows";
      exec = "code.cmd %F";
      mimeType = [ "text/plain" "application/json" "text/x-markdown" ];
      categories = [ "Development" "TextEditor" ];
    };
    
    explorer-windows = {
      name = "File Explorer (Windows)";
      comment = "Open Windows File Explorer";
      exec = "explorer.exe %f";
      mimeType = [ "inode/directory" ];
      categories = [ "System" "FileManager" ];
    };
  };
}