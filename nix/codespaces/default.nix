# GitHub Codespaces specialized configuration
{ config, lib, pkgs, ... }:

{
  # Codespaces-specific environment
  home.username = "vscode";
  home.homeDirectory = "/home/vscode";
  home.stateVersion = "24.05";
  
  # GitHub Codespaces特化パッケージ
  home.packages = with pkgs; [
    # Development essentials
    git
    gh  # GitHub CLI
    starship
    neovim
    
    # Nix development tools
    nil
    nixpkgs-fmt
    nix-tree
    home-manager
    
    # Enhanced shell utilities
    jq
    yq-go
    bat
    eza
    fd
    ripgrep
    tree
    htop
    
    # Build and automation tools
    just
    direnv
    
    # Security tools
    age
    sops
    
    # Node.js ecosystem (for Claude CLI)
    nodejs_20
    npm-check-updates
    
    # Development languages
    python3
    go
    
    # Container tools (available in Codespaces)
    # docker and docker-compose are pre-installed
    
    # Text processing
    gnused
    gawk
    
    # Network tools
    curl
    wget
    
    # Archive tools
    unzip
    gzip
    tar
  ];
  
  # Git configuration optimized for Codespaces
  programs.git = {
    enable = true;
    userName = lib.mkDefault "GitHub Codespaces";
    userEmail = lib.mkDefault "codespaces@github.com";
    
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = false;  # Safer for collaborative environments
      push.autoSetupRemote = true;
      core.editor = "nvim";
      
      # Codespaces-specific optimizations
      core.autocrlf = "input";
      core.longpaths = true;
      credential.helper = "store";
      
      # GitHub integration
      hub.protocol = "https";
    };
    
    aliases = {
      st = "status";
      co = "checkout";
      br = "branch";
      ci = "commit";
      df = "diff";
      lg = "log --oneline --graph --decorate";
    };
  };
  
  # GitHub CLI configuration
  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "https";
      editor = "nvim";
      prompt = "enabled";
      pager = "less";
    };
  };
  
  # Enhanced Starship prompt for Codespaces
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      format = "$username$hostname$directory$git_branch$git_status$git_state$git_metrics$package$nodejs$python$golang$cmd_duration$line_break$jobs$character";
      
      # Codespaces identification
      username = {
        show_always = true;
        style_user = "blue bold";
        style_root = "red bold";
        format = "[$user]($style)";
      };
      
      hostname = {
        ssh_only = false;
        format = "@[$hostname](bold yellow) ";
        trim_at = ".";
      };
      
      directory = {
        style = "cyan";
        truncation_length = 3;
        truncate_to_repo = true;
        format = "[$path]($style)[$read_only]($read_only_style) ";
      };
      
      git_branch = {
        format = "[$symbol$branch]($style) ";
        style = "bright-green";
        symbol = "🌱 ";
      };
      
      git_status = {
        format = "([\\[$all_status$ahead_behind\\]]($style) )";
        style = "red";
      };
      
      character = {
        success_symbol = "[❯](purple)";
        error_symbol = "[❯](red)";
        vimcmd_symbol = "[❮](green)";
      };
      
      # Development environment indicators
      nodejs = {
        format = "[$symbol($version )]($style)";
        style = "green";
      };
      
      python = {
        format = "[$symbol$pyenv_prefix($version )($virtualenv )]($style)";
        style = "yellow";
      };
      
      golang = {
        format = "[$symbol($version )]($style)";
        style = "cyan";
      };
      
      cmd_duration = {
        format = "[$duration]($style) ";
        style = "yellow";
      };
    };
  };
  
  # Zsh configuration optimized for development
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    
    # Codespaces-specific aliases
    shellAliases = {
      # Enhanced ls
      ls = "eza --color=auto --group-directories-first";
      ll = "eza -la --color=auto --group-directories-first";
      la = "eza -la --color=auto --group-directories-first";
      tree = "eza --tree";
      
      # Enhanced cat and grep
      cat = "bat --style=auto";
      grep = "rg";
      find = "fd";
      
      # Git shortcuts
      g = "git";
      gs = "git status";
      ga = "git add";
      gaa = "git add --all";
      gc = "git commit";
      gcm = "git commit -m";
      gp = "git push";
      gl = "git pull";
      gco = "git checkout";
      gb = "git branch";
      gd = "git diff";
      glog = "git log --oneline --graph --decorate";
      
      # GitHub CLI shortcuts  
      ghpr = "gh pr create";
      ghpv = "gh pr view";
      ghpm = "gh pr merge";
      ghis = "gh issue create";
      ghiv = "gh issue view";
      ghrc = "gh repo clone";
      
      # Dotfiles management
      rebuild = "home-manager switch --flake .#codespaces";
      check = "nix flake check";
      fmt = "nixpkgs-fmt";
      
      # Development shortcuts
      serve = "python3 -m http.server 8000";
      json = "jq .";
      yaml = "yq eval";
      
      # Container shortcuts (use system docker)
      dps = "docker ps";
      dpa = "docker ps -a";
      di = "docker images";
      dc = "docker-compose";
      
      # Claude CLI
      claude = "claude";
      ai = "claude";
    };
    
    # Environment variables for Codespaces
    sessionVariables = {
      EDITOR = "nvim";
      PAGER = "bat";
      BROWSER = "echo";  # No browser in Codespaces
      
      # Dotfiles environment markers
      DOTFILES_ENVIRONMENT = "codespaces";
      DOTFILES_PLATFORM = "linux";
      GITHUB_CODESPACES = "true";
      
      # Development environment
      NODE_ENV = "development";
      
      # Optimization for container environments
      NIXPKGS_ALLOW_UNFREE = "1";
    };
    
    # Codespaces-specific shell functions and initialization
    initContent = ''
      # Working directory management
      function cdrepo() {
        cd /workspaces/dotfiles
      }
      
      # Dotfiles management functions
      function dotfiles-rebuild() {
        echo "🔄 Rebuilding dotfiles configuration for Codespaces..."
        cd /workspaces/dotfiles
        home-manager switch --flake .#codespaces
        echo "✅ Dotfiles rebuild completed!"
      }
      
      function dotfiles-health() {
        echo "🏥 Running dotfiles health check..."
        cd /workspaces/dotfiles
        if [[ -f "./system-health-check.sh" ]]; then
          ./system-health-check.sh
        else
          echo "Health check script not found"
        fi
      }
      
      function dotfiles-status() {
        echo "📊 Dotfiles environment status:"
        echo "  • Environment: $DOTFILES_ENVIRONMENT"
        echo "  • Platform: $DOTFILES_PLATFORM"
        echo "  • User: $(whoami)"
        echo "  • Home: $HOME"
        echo "  • Working Dir: $(pwd)"
        echo "  • Git Branch: $(git branch --show-current 2>/dev/null || echo 'not a git repo')"
        echo "  • Nix Store: $(du -sh /nix/store 2>/dev/null | cut -f1 || echo 'not available')"
      }
      
      # GitHub workflow helpers
      function gh-quick-pr() {
        local title="$1"
        local body="$2"
        if [[ -z "$title" ]]; then
          echo "Usage: gh-quick-pr 'PR title' 'Optional description'"
          return 1
        fi
        gh pr create --title "$title" --body "$body" --assignee @me
      }
      
      function gh-issue-quick() {
        local title="$1"
        local body="$2"
        if [[ -z "$title" ]]; then
          echo "Usage: gh-issue-quick 'Issue title' 'Optional description'"
          return 1
        fi
        gh issue create --title "$title" --body "$body" --assignee @me
      }
      
      # Development helpers
      function nix-search-local() {
        nix search nixpkgs "$1" | head -20
      }
      
      function containers-status() {
        echo "🐳 Container status:"
        docker ps --format "table {{.Names}}\\t{{.Status}}\\t{{.Ports}}"
        echo ""
        echo "📦 Docker images:"
        docker images --format "table {{.Repository}}\\t{{.Tag}}\\t{{.Size}}"
      }
      
      # Auto-change to workspace directory on shell start
      if [[ "$PWD" == "$HOME" ]] && [[ -d "/workspaces/dotfiles" ]]; then
        cd /workspaces/dotfiles
        echo "🏠 Switched to dotfiles workspace"
      fi
      
      # Welcome message
      if [[ -n "$GITHUB_CODESPACES" ]]; then
        echo "🚀 Welcome to GitHub Codespaces dotfiles environment!"
        echo "💡 Try: dotfiles-status, dotfiles-health, or claude"
      fi
    '';
  };
  
  # Neovim configuration for development
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    
    extraConfig = ''
      " Basic settings
      set number
      set relativenumber
      set expandtab
      set tabstop=2
      set shiftwidth=2
      set smartindent
      set autoindent
      set wrap
      set linebreak
      set scrolloff=5
      set sidescrolloff=5
      
      " Search settings
      set ignorecase
      set smartcase
      set incsearch
      set hlsearch
      
      " Visual improvements
      syntax enable
      set termguicolors
      set signcolumn=yes
      set cursorline
      
      " File handling
      set autoread
      set backup
      set backupdir=~/.cache/nvim/backup
      set directory=~/.cache/nvim/swap
      set undofile
      set undodir=~/.cache/nvim/undo
      
      " Create cache directories if they don't exist
      call mkdir(&backupdir, 'p', 0700)
      call mkdir(&directory, 'p', 0700)
      call mkdir(&undodir, 'p', 0700)
      
      " GitHub Codespaces optimizations
      set mouse=a
      set clipboard=unnamedplus
      
      " File type specific settings
      autocmd FileType nix setlocal shiftwidth=2 tabstop=2
      autocmd FileType yaml setlocal shiftwidth=2 tabstop=2
      autocmd FileType json setlocal shiftwidth=2 tabstop=2
      autocmd FileType markdown setlocal wrap linebreak
    '';
  };
  
  # Direnv for project-specific environments
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };
  
  # Bat configuration (enhanced cat)
  programs.bat = {
    enable = true;
    config = {
      theme = "GitHub";
      style = "numbers,changes,header";
      pager = "less -FR";
    };
  };
  
  # Enable home-manager management
  programs.home-manager.enable = true;
  
  # XDG directories for proper file organization
  xdg.enable = true;
}