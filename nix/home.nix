{ config, pkgs, username, homeDirectory, dotfilesDirectory, ... }:

{
  # Basic home-manager configuration
  home = {
    username = username;
    homeDirectory = homeDirectory;
    stateVersion = "24.05";
  };

  # User packages
  home.packages = with pkgs; [
    # Additional CLI tools
    curl
    wget
    htop
    btop
    fd
    bat
    eza  # Modern ls replacement
    zoxide  # Smart cd
    fzf
    delta  # Better git diff
    
    # Development tools
    direnv
    just  # Command runner
    lazygit  # Git TUI
    tig      # Git text interface
    gitui    # Another Git TUI
    
    # CLI tools from uninstall logs
    # bitwarden-cli  # Marked as broken in nixpkgs
    
    # File utilities
    unzip
    gzip
    rsync
    tree
    
    # Network tools
    nmap
    speedtest-cli
    # tshark included in wireshark system package
    
    # Media tools
    imagemagick
    ffmpeg
    
    # Productivity
    pandoc   # Document converter
    
    # Text processing
    jq       # JSON processor
    yq       # YAML processor
    
    # System monitoring
    lsof
    
    # Additional development tools
    act      # Run GitHub Actions locally
    gh       # GitHub CLI
    
    # Optional: Add more packages as needed
  ];

  # Program configurations
  programs = {
    # Home Manager itself
    home-manager.enable = true;

    # Shell configuration - integrate with existing zshrc
    zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      
      # Source existing zshrc configuration from dotfiles
      initExtraFirst = ''
        # Source existing zshrc configuration
        if [[ -f "${dotfilesDirectory}/configs/zsh/zshrc" ]]; then
          source "${dotfilesDirectory}/configs/zsh/zshrc"
        fi
      '';
      
      shellAliases = {
        # Modern CLI replacements
        ls = "eza --color=auto --icons";
        ll = "eza -l --color=auto --icons";
        la = "eza -la --color=auto --icons";
        tree = "eza --tree --color=auto --icons";
        cat = "bat";
        find = "fd";
        cd = "z";  # zoxide
        
        # Git shortcuts
        g = "git";
        gs = "git status";
        ga = "git add";
        gc = "git commit";
        gp = "git push";
        gl = "git pull";
        lg = "lazygit";
        
        # System shortcuts
        reload = "exec $SHELL";
        path = "echo $PATH | tr ':' '\n'";
        
        # nix shortcuts
        nrs = "darwin-rebuild switch --flake ~/dotfiles/nix";
        hms = "home-manager switch --flake ~/dotfiles/nix";
        
        # dotfiles management shortcuts
        install = "~/dotfiles/install.sh";
        install-force = "~/dotfiles/install.sh --force";
        backup-list = "~/dotfiles/install.sh --list-backups";
      };
    };

    # Git configuration
    git = {
      enable = true;
      # Note: Keep personal git config in separate file (excluded from git)
      includes = [
        { path = "${homeDirectory}/.gitconfig.personal"; }
      ];
      
      # Global git configuration
      extraConfig = {
        init.defaultBranch = "main";
        push.default = "simple";
        pull.rebase = true;
        core.editor = "nvim";
        diff.tool = "vimdiff";
        merge.tool = "vimdiff";
      };
    };

    # Starship prompt - enabled with default configuration
    starship = {
      enable = true;
      # Use home-manager managed configuration for now
      # Manual starship.toml management via home.file
    };

    # tmux - enabled with basic configuration  
    tmux = {
      enable = true;
      # Use home-manager managed configuration for now
      # Manual tmux.conf management via home.file
    };

    # Neovim
    neovim = {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
      
      # Use existing neovim config from dotfiles
      # Note: LazyNvim will handle plugin management
    };

    # direnv for project-specific environments
    direnv = {
      enable = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };

    # fzf for fuzzy finding
    fzf = {
      enable = true;
      enableZshIntegration = true;
      defaultCommand = "fd --type f";
      defaultOptions = [ "--height 40%" "--border" ];
    };

    # zoxide for smart directory jumping
    zoxide = {
      enable = true;
      enableZshIntegration = true;
    };

    # bat for syntax highlighting
    bat = {
      enable = true;
      config = {
        theme = "TwoDark";
        style = "numbers,changes,header";
      };
    };
  };

  # File management - Temporarily disabled due to pure evaluation mode
  # Will be enabled once flake configuration is properly set up for impure builds
  # home.file = {
  #   # Terminal configurations
  #   ".config/wezterm/wezterm.lua".source = "${dotfilesDirectory}/configs/terminal/wezterm.lua";
  #   ".config/starship.toml".source = "${dotfilesDirectory}/configs/terminal/starship.toml";
  #   ".tmux.conf".source = "${dotfilesDirectory}/configs/terminal/tmux.conf";
  # };

  # Session variables
  home.sessionVariables = {
    EDITOR = "nvim";
    BROWSER = "arc";
    TERMINAL = "wezterm";
    
    # Development paths
    DOTFILES = dotfilesDirectory;
    
    # Tool configurations
    BAT_THEME = "TwoDark";
    FZF_DEFAULT_COMMAND = "fd --type f";
    
    # Nix-specific
    NIX_PATH = "$HOME/.nix-defexpr/channels:nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixpkgs:darwin-config=$HOME/.nixpkgs/darwin-configuration.nix";
  };

  # XDG directories
  xdg = {
    enable = true;
    configHome = "${homeDirectory}/.config";
    dataHome = "${homeDirectory}/.local/share";
    cacheHome = "${homeDirectory}/.cache";
  };

  # Services (user-level)
  services = {
    # Syncthing for file synchronization
    # syncthing.enable = true;
    
    # Custom services can be added here
  };

  # Platform-specific configurations
  targets.darwin = {
    # Darwin-specific home-manager configurations
    defaults = {
      # Custom plist configurations can go here
    };
  };
}