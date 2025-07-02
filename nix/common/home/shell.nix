# Cross-platform shell configuration
{ config, lib, pkgs, platformInfo ? {}, ... }:

{
  # Home Manager needs state version for compatibility
  home.stateVersion = lib.mkDefault "23.11";
  
  # Basic home configuration (can be overridden)
  home.username = lib.mkDefault "yuki";  # Force lowercase for consistency  
  home.homeDirectory = lib.mkDefault (if pkgs.stdenv.isDarwin then "/Users/yuki" else "/home/yuki");
  
  # Zsh configuration (works on all platforms)
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    
    # Platform-agnostic aliases with modern tools
    shellAliases = {
      # Core modern replacements (if available, otherwise fallback)
      ls = "eza --icons || ls --color=auto";
      ll = "eza -la --icons --git || ls -la";
      la = "eza -la --icons --git || ls -la";
      tree = "eza --tree --icons || tree";
      cat = "bat || cat";
      grep = "rg || grep";
      find = "fd || find";
      ps = "procs || ps";
      top = "btm || top";
      du = "dust || du";
      df = "duf || df";
      
      # Git shortcuts
      g = "git";
      gs = "git status";
      ga = "git add";
      gc = "git commit";
      gp = "git push";
      gl = "git pull";
      lg = "lazygit || git log --oneline --graph";
      
      # System info
      neofetch = "fastfetch || neofetch";
      
      # File management
      fm = "yazi || ranger || mc";
      
      # Directory navigation
      ".." = "cd ..";
      "..." = "cd ../..";
      "cd.." = "cd ..";
      
      # Nix shortcuts
      nr = "nix run";
      ns = "nix search";
      nf = "nix flake";
      
      # Platform defaults (macOS assumed for now)
      nrs = "nix run nix-darwin -- switch --flake .";
      hms = "home-manager switch --flake .";
      
      # System specific (macOS)
      brew = "/opt/homebrew/bin/brew";
    };
    
    # Environment variables (basic setup) 
    sessionVariables = lib.mkMerge [
      {
        EDITOR = "nvim";
        PAGER = "bat";
        PATH = "$HOME/.local/bin:/opt/homebrew/bin:$PATH";
        DOTFILES = "${config.home.homeDirectory}/dotfiles";
        
        # Python Nix integration
        PYTHONSTARTUP = "${config.home.homeDirectory}/dotfiles/configs/python/.pythonrc";
        PIP_CONFIG_FILE = "${config.home.homeDirectory}/dotfiles/configs/python/pip.conf";
        PYTHONDONTWRITEBYTECODE = "1";  # Prevent .pyc files
        PYTHONUNBUFFERED = "1";         # Force unbuffered output
        
        # Node.js Nix integration
        NPM_CONFIG_USERCONFIG = "${config.home.homeDirectory}/dotfiles/configs/nodejs/.npmrc";
        NODE_OPTIONS = "--max-old-space-size=4096";  # Increase memory limit
        
        # Rust Nix integration
        CARGO_HOME = "${config.home.homeDirectory}/.cargo";
        RUSTUP_HOME = "${config.home.homeDirectory}/.rustup";
        RUST_BACKTRACE = "1";  # Enable backtraces
        
        # Go Nix integration
        GOPATH = "${config.home.homeDirectory}/go";
        GOBIN = "${config.home.homeDirectory}/go/bin";
        GO111MODULE = "on";
        GOPROXY = "https://proxy.golang.org,direct";
        
        # Ruby Nix integration
        GEM_HOME = "${config.home.homeDirectory}/.gem";
        GEM_PATH = "${config.home.homeDirectory}/.gem";
        GEMRC = "${config.home.homeDirectory}/dotfiles/configs/ruby/.gemrc";
        
        # PHP Nix integration
        COMPOSER_HOME = "${config.home.homeDirectory}/.composer";
        COMPOSER_CACHE_DIR = "${config.home.homeDirectory}/.composer/cache";
        
        # Java Nix integration
        JAVA_HOME = "/nix/store/*-openjdk-*/lib/openjdk";  # Will be resolved by Nix
        MAVEN_OPTS = "-Xmx2048m -XX:MaxPermSize=256m";
        M2_HOME = "${config.home.homeDirectory}/.m2";
        
        # macOS specific (safe to set on all platforms)
        HOMEBREW_NO_ANALYTICS = "1"; 
        HOMEBREW_NO_INSECURE_REDIRECT = "1";
      }
    ];
    
    # Platform-specific initialization
    initContent = ''
      # Atuin shell history (if available)
      if command -v atuin &> /dev/null; then
        eval "$(atuin init zsh)"
      fi
      
      # Zoxide initialization (if available)
      if command -v zoxide &> /dev/null; then
        eval "$(zoxide init zsh)"
      fi
      
      # fzf configuration (if available)
      if command -v fzf &> /dev/null; then
        export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git || find . -type f'
        export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
        export FZF_ALT_C_COMMAND="fd --type d --hidden --follow --exclude .git || find . -type d"
      fi
      
      # Universal shell functions
      function mkcd() {
        mkdir -p "$1" && cd "$1"
      }
      
      function extract() {
        case $1 in
          *.tar.bz2)   tar xjf $1     ;;
          *.tar.gz)    tar xzf $1     ;;
          *.bz2)       bunzip2 $1     ;;
          *.rar)       unrar x $1     ;;
          *.gz)        gunzip $1      ;;
          *.tar)       tar xf $1      ;;
          *.tbz2)      tar xjf $1     ;;
          *.tgz)       tar xzf $1     ;;
          *.zip)       unzip $1       ;;
          *.Z)         uncompress $1  ;;
          *.7z)        7z x $1        ;;
          *)           echo "'$1' cannot be extracted via extract()" ;;
        esac
      }
      
      # macOS specific shell setup (safe to run on all platforms)
      if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      fi
      
      
      # WezTerm shell integration for command completion notifications
      if [[ "$TERM_PROGRAM" == "WezTerm" ]]; then
        # Enable preexec and precmd hooks for zsh
        autoload -Uz add-zsh-hook
        
        # Track command execution start time
        function __wezterm_preexec() {
          __wezterm_command_start_time=$SECONDS
          __wezterm_command_name="$1"
        }
        
        # Send bell notification for long-running commands when complete
        function __wezterm_precmd() {
          if [[ -n "$__wezterm_command_start_time" ]]; then
            local elapsed=$((SECONDS - __wezterm_command_start_time))
            if [[ $elapsed -gt 3 ]]; then
              # Send bell for commands longer than 3 seconds (WezTerm converts to toast)
              printf '\a'
              # Alternative: use WezTerm escape sequence for better control
              printf '\e]9;%s\e\\' "Command completed in ''${elapsed}s"
            fi
            unset __wezterm_command_start_time
            unset __wezterm_command_name
          fi
        }
        
        # Register hooks with zsh
        add-zsh-hook preexec __wezterm_preexec
        add-zsh-hook precmd __wezterm_precmd
        
        # Claude Code specific notification wrapper
        claude() {
          command claude "$@"
          local exit_code=$?
          # Always send notification when claude command completes
          printf '\a'
          printf '\e]9;%s\e\\' "Claude Code session completed"
          return $exit_code
        }
        
        # General long-running command wrapper
        notify() {
          "$@"
          local exit_code=$?
          printf '\a'
          printf '\e]9;%s\e\\' "Command '$1' completed with exit code $exit_code"
          return $exit_code
        }
      fi
    '';
  };

  # Starship prompt (universal)
  programs.starship = {
    enable = true;
    settings = {
      format = lib.concatStrings [
        "$username"
        "$hostname"
        "$directory"
        "$git_branch"
        "$git_state"
        "$git_status"
        "$cmd_duration"
        "$line_break"
        "$character"
      ];
      
      character = {
        success_symbol = "[➜](bold green)";
        error_symbol = "[➜](bold red)";
      };
      
      directory = {
        truncation_length = 3;
        truncate_to_repo = true;
      };
      
      git_branch = {
        symbol = "🌱 ";
      };
      
      # Platform-specific customizations
      hostname = {
        ssh_only = false;
        format = "[@$hostname](bold blue) ";
        disabled = false;  # Enable for all platforms
      };
    };
  };

  # Direnv (when available)
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  # Zoxide (modern cd replacement) - disabled for compatibility
  # programs.zoxide = {
  #   enable = true;
  #   enableZshIntegration = true;
  # };

  # FZF (fuzzy finder) with enhanced configuration
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultCommand = "fd --type f --hidden --follow --exclude .git || find . -type f";
    defaultOptions = [
      "--height=40%"
      "--layout=reverse"
      "--border"
      "--preview='bat --style=numbers --color=always --line-range :500 {} 2>/dev/null || cat {}'"
    ];
    historyWidgetOptions = [
      "--sort"
      "--exact"
    ];
  };

  # Atuin (shell history) configuration
  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      auto_sync = true;
      sync_frequency = "5m";
      search_mode = "fuzzy";
      filter_mode = "global";
      workspaces = true;
      secrets_filter = true;
      style = "compact";
      show_preview = true;
      max_preview_height = 4;
      sync = {
        records = true;
      };
    };
  };
}