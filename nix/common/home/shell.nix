# Cross-platform shell configuration
{ config, lib, pkgs, platformInfo ? {}, ... }:

{
  # Home Manager needs state version for compatibility
  home.stateVersion = lib.mkDefault "23.11";
  
  # Basic home configuration (can be overridden)
  home.username = lib.mkDefault "yuki";
  home.homeDirectory = lib.mkDefault (if pkgs.stdenv.isDarwin then "/Users/yuki" else "/home/yuki");
  # Zsh configuration (works on all platforms)
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    
    # Platform-agnostic aliases
    shellAliases = {
      # Modern tool replacements (when available)
      ls = if lib.elem pkgs.eza (platformInfo.packages or []) then "eza" else "ls --color=auto";
      ll = if lib.elem pkgs.eza (platformInfo.packages or []) then "eza -la" else "ls -la";
      cat = if lib.elem pkgs.bat (platformInfo.packages or []) then "bat" else "cat";
      find = if lib.elem pkgs.fd (platformInfo.packages or []) then "fd" else "find";
      grep = if lib.elem pkgs.ripgrep (platformInfo.packages or []) then "rg" else "grep";
      
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
      
    } // lib.optionalAttrs (platformInfo.platform or "unknown" == "darwin") {
      # macOS specific aliases
      nrs = "nix run nix-darwin -- switch --flake .";
      hms = "home-manager switch --flake .";
      
    } // lib.optionalAttrs (platformInfo.platform or "unknown" == "nixos") {
      # NixOS specific aliases
      nrs = "sudo nixos-rebuild switch --flake .";
      hms = "home-manager switch --flake .";
      
    } // lib.optionalAttrs (lib.elem (platformInfo.platform or "unknown") ["linux" "wsl"]) {
      # Linux/WSL specific aliases
      hms = "home-manager switch --flake .";
      
    } // lib.optionalAttrs (platformInfo.platform or "unknown" == "android") {
      # Android/nix-on-droid specific aliases
      nrs = "nix-on-droid switch --flake .";
    };
    
    # Environment variables
    sessionVariables = {
      EDITOR = "vim";
      PAGER = if lib.elem pkgs.bat (platformInfo.packages or []) then "bat" else "less";
      
      # Platform-specific paths
      DOTFILES = "${config.home.homeDirectory}/dotfiles";
      
    } // lib.optionalAttrs (platformInfo.platform or "unknown" == "darwin") {
      # macOS specific environment
      HOMEBREW_NO_ANALYTICS = "1";
      HOMEBREW_NO_INSECURE_REDIRECT = "1";
      
    } // lib.optionalAttrs (platformInfo.platform or "unknown" == "wsl") {
      # WSL specific environment
      DISPLAY = ":0.0";
      
    } // lib.optionalAttrs (platformInfo.platform or "unknown" == "android") {
      # Android specific environment
      TERMUX_PKG_FORMAT = "nix";
    };
    
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
      
      ${lib.optionalString (platformInfo.platform or "unknown" == "darwin") ''
        # macOS specific shell setup
        if [[ -f /opt/homebrew/bin/brew ]]; then
          eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
        
        # WezTerm shell integration for command completion notifications
        if [[ "$TERM_PROGRAM" == "WezTerm" ]]; then
          # Track command execution start time
          preexec() {
            __wezterm_command_start_time=$SECONDS
            __wezterm_set_user_var WEZTERM_PROG "$1"
          }
          
          # Send notification for long-running commands when complete
          precmd() {
            if [[ -n "$__wezterm_command_start_time" ]]; then
              local elapsed=$((SECONDS - __wezterm_command_start_time))
              if [[ $elapsed -gt 5 ]]; then
                # Send notification for commands longer than 5 seconds
                printf "\033]777;notify;Command Completed;Command finished in %d seconds\033\\" "$elapsed"
              fi
              unset __wezterm_command_start_time
            fi
          }
        fi
      ''}
      
      ${lib.optionalString (platformInfo.platform or "unknown" == "wsl") ''
        # WSL specific shell setup
        export PATH="$PATH:/mnt/c/Windows/System32"
      ''}
      
      ${lib.optionalString (platformInfo.platform or "unknown" == "android") ''
        # Android/Termux specific shell setup
        export PATH="$PATH:$PREFIX/bin"
      ''}
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
        disabled = platformInfo.platform or "unknown" == "android";
      };
    };
  };

  # Direnv (when available)
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  # Zoxide (modern cd replacement)
  programs.zoxide = lib.mkIf (lib.elem pkgs.zoxide (platformInfo.packages or [])) {
    enable = true;
    enableZshIntegration = true;
  };

  # FZF (fuzzy finder)
  programs.fzf = lib.mkIf (lib.elem pkgs.fzf (platformInfo.packages or [])) {
    enable = true;
    enableZshIntegration = true;
    defaultOptions = [
      "--height 40%"
      "--layout=reverse"
      "--border"
      "--inline-info"
    ];
  };
}