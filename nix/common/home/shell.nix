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
    
    # Platform-agnostic aliases
    shellAliases = {
      # Basic aliases (no platformInfo dependency for compatibility)
      ls = "ls --color=auto";
      ll = "ls -la";
      cat = "cat";
      find = "find";
      grep = "grep";
      
      # Git shortcuts
      g = "git";
      gs = "git status";
      ga = "git add";
      gc = "git commit";
      gp = "git push";
      gl = "git pull";
      
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
    };
    
    # Environment variables (basic setup) 
    sessionVariables = lib.mkMerge [
      {
        EDITOR = "vim";
        PAGER = "less";
        DOTFILES = "${config.home.homeDirectory}/dotfiles";
        # macOS specific (safe to set on all platforms)
        HOMEBREW_NO_ANALYTICS = "1"; 
        HOMEBREW_NO_INSECURE_REDIRECT = "1";
      }
    ];
    
    # Platform-specific initialization
    initContent = ''
      
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
        # Track command execution start time
        preexec() {
          __wezterm_command_start_time=$SECONDS
          __wezterm_command_name="$1"
        }
        
        # Send bell notification for long-running commands when complete
        precmd() {
          if [[ -n "$__wezterm_command_start_time" ]]; then
            local elapsed=$((SECONDS - __wezterm_command_start_time))
            if [[ $elapsed -gt 10 ]]; then
              # Send bell for commands longer than 10 seconds (WezTerm converts to toast)
              echo -e "\a"
            fi
            unset __wezterm_command_start_time
            unset __wezterm_command_name
          fi
        }
        
        # Claude Code specific notification wrapper
        claude() {
          command claude "$@"
          # Always send bell notification when claude command completes
          echo -e "\a"
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

  # FZF (fuzzy finder) - disabled for compatibility
  # programs.fzf = {
  #   enable = true;
  #   enableZshIntegration = true;
  #   defaultOptions = [
  #     "--height 40%"
  #     "--layout=reverse"
  #     "--border"
  #     "--inline-info"
  #   ];
  # };
}