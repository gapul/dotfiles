# Modern CLI Tools Integration (Fixed Version)
# Phase 5: Enhanced CLI experience with modern alternatives

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.development.modern-cli;
in
{
  options.dotfiles.development.modern-cli = {
    enable = mkEnableOption "Modern CLI tools integration";
    
    profile = mkOption {
      type = types.enum [ "minimal" "standard" "full" ];
      default = "standard";
      description = "Modern CLI profile level";
    };
    
    # Individual tool toggles
    navigation = mkEnableOption "Navigation tools (eza, fd, zoxide)";
    content = mkEnableOption "Content tools (bat, ripgrep)";
    process = mkEnableOption "Process tools (bottom, procs)";
    git = mkEnableOption "Git tools (lazygit, delta)";
    file-manager = mkEnableOption "File manager (yazi)";
    system-info = mkEnableOption "System info (fastfetch)";
    data-analysis = mkEnableOption "Data analysis (visidata)";
    atuin = mkEnableOption "Shell history (atuin)";
    starship = mkEnableOption "Shell prompt (starship)";
    zoxide = mkEnableOption "Smart cd (zoxide)";
  };

  config = mkIf cfg.enable {
    # Auto-enable features based on profile
    dotfiles.development.modern-cli = {
      navigation = mkDefault (cfg.profile == "standard" || cfg.profile == "full");
      content = mkDefault (cfg.profile == "standard" || cfg.profile == "full");
      process = mkDefault (cfg.profile == "full");
      git = mkDefault (cfg.profile == "standard" || cfg.profile == "full");
      file-manager = mkDefault (cfg.profile == "full");
      system-info = mkDefault (cfg.profile == "standard" || cfg.profile == "full");
      data-analysis = mkDefault (cfg.profile == "full");
      atuin = mkDefault (cfg.profile == "standard" || cfg.profile == "full");
      starship = mkDefault (cfg.profile == "standard" || cfg.profile == "full");
      zoxide = mkDefault (cfg.profile == "standard" || cfg.profile == "full");
    };

    # Install packages based on enabled features
    home-manager.users.yuki.home.packages = with pkgs; [
      # Always include core modern CLI tools
    ] ++ optionals cfg.navigation [
      eza         # Modern ls replacement
      fd          # Modern find replacement
    ] ++ optionals cfg.content [
      bat         # Modern cat replacement
      ripgrep     # Modern grep replacement
    ] ++ optionals cfg.process [
      bottom      # Modern top replacement
      procs       # Modern ps replacement
    ] ++ optionals cfg.git [
      lazygit     # Terminal UI for git
      delta       # Better git diff
    ] ++ optionals cfg.file-manager [
      yazi        # Terminal file manager
    ] ++ optionals cfg.system-info [
      fastfetch   # System info display
    ] ++ optionals cfg.data-analysis [
      visidata    # Terminal data analysis
    ] ++ optionals cfg.atuin [
      atuin       # Shell history
    ];

    # Zoxide configuration
    home-manager.users.yuki.programs.zoxide = mkIf cfg.zoxide {
      enable = true;
      enableZshIntegration = true;
      enableBashIntegration = true;
      options = [ "--cmd cd" ];
    };

    # Starship prompt configuration
    home-manager.users.yuki.programs.starship = mkIf cfg.starship {
      enable = true;
      enableZshIntegration = true;
      enableBashIntegration = true;
      
      settings = {
        format = lib.concatStrings [
          "$username"
          "$hostname"
          "$directory"
          "$git_branch"
          "$git_status"
          "$git_state"
          "$python"
          "$nodejs"
          "$rust"
          "$golang"
          "$nix_shell"
          "$cmd_duration"
          "$line_break"
          "$jobs"
          "$character"
        ];
        
        # Minimal prompt for speed
        add_newline = false;
        
        # Directory configuration
        directory = {
          style = "bold cyan";
          truncation_length = 3;
          truncation_symbol = "…/";
          fish_style_pwd_dir_length = 1;
          use_logical_path = true;
        };
        
        # Git configuration
        git_branch = {
          symbol = " ";
          style = "bold purple";
        };
        
        git_status = {
          style = "bold yellow";
          conflicted = "🏳";
          ahead = "🏎💨";
          behind = "😰";
          diverged = "😵";
          up_to_date = "✓";
          untracked = "🤷";
          stashed = "📦";
          modified = "📝";
          staged = "➕";
          renamed = "👅";
          deleted = "🗑";
        };
        
        # Language configurations
        nodejs = {
          symbol = " ";
          detect_extensions = ["js" "mjs" "cjs" "ts" "tsx"];
          detect_files = ["package.json" ".node-version"];
          detect_folders = ["node_modules"];
        };
        
        python = {
          symbol = " ";
          detect_extensions = ["py"];
          detect_files = [".python-version" "Pipfile" "requirements.txt" "pyproject.toml"];
        };
        
        rust = {
          symbol = " ";
          detect_extensions = ["rs"];
          detect_files = ["Cargo.toml"];
        };
        
        golang = {
          symbol = " ";
          detect_extensions = ["go"];
          detect_files = ["go.mod" "go.sum"];
        };
        
        nix_shell = {
          symbol = " ";
          style = "bold blue";
          impure_msg = "[impure shell]";
          pure_msg = "[pure shell]";
        };
        
        character = {
          success_symbol = "[❯](purple)";
          error_symbol = "[❯](red)";
          vimcmd_symbol = "[❮](green)";
        };
        
        cmd_duration = {
          style = "yellow";
          show_milliseconds = false;
        };
      };
    };

    # Shell aliases for modern CLI tools
    home-manager.users.yuki.programs.zsh.shellAliases = mkMerge [
      # Navigation aliases
      (mkIf cfg.navigation {
        ls = "eza --color=auto --group-directories-first";
        ll = "eza -la --color=auto --group-directories-first";
        la = "eza -la --color=auto --group-directories-first";
        tree = "eza --tree";
        find = "fd";
      })
      
      # Content aliases  
      (mkIf cfg.content {
        cat = "bat --style=auto";
        grep = "rg";
        rg = "rg --smart-case";
      })
      
      # Process aliases
      (mkIf cfg.process {
        top = "bottom";
        htop = "bottom";
        ps = "procs";
      })
      
      # Git aliases
      (mkIf cfg.git {
        lazygit = "lazygit";
        lg = "lazygit";
        git-ui = "lazygit";
      })
      
      # File manager
      (mkIf cfg.file-manager {
        fm = "yazi";
        files = "yazi";
      })
      
      # System info
      (mkIf cfg.system-info {
        info = "fastfetch";
        sysinfo = "fastfetch";
        neofetch = "fastfetch";
      })
      
      # Data analysis
      (mkIf cfg.data-analysis {
        data = "visidata";
        vd = "visidata";
      })
      
      # Atuin
      (mkIf cfg.atuin {
        history = "atuin search";
        h = "atuin search";
      })
    ];

    # Enhanced shell integration
    home-manager.users.yuki.programs.zsh.initContent = mkMerge [
      (mkIf cfg.navigation ''
        # Zoxide integration
        eval "$(zoxide init zsh)"
        alias cd="z"
        alias zi="zi"
        alias zq="zoxide query"
        alias zr="zoxide remove"
      '')
      
      (mkIf cfg.atuin ''
        # Atuin integration
        eval "$(atuin init zsh)"
        
        # Atuin configuration
        export ATUIN_NOBIND="true"
        bindkey '^r' _atuin_search_widget
      '')
      
      (mkIf cfg.starship ''
        # Starship integration (automatic with programs.starship.enable)
      '')
      
      # Common functions
      ''
        # Modern CLI helper functions
        
        # Enhanced ls with tree view
        ${if cfg.navigation then ''
          llt() {
            eza --tree --level=''${1:-2}
          }
        '' else ''
          llt() {
            ls -la
          }
        ''}
        
        # Smart find and grep combination
        ${if cfg.navigation && cfg.content then ''
          findgrep() {
            fd "$1" | xargs rg "$2"
          }
        '' else ''
          findgrep() {
            find . -name "$1" -exec grep -l "$2" {} \;
          }
        ''}
        
        # Quick file preview
        ${if cfg.content then ''
          preview() {
            bat --style=header,grid --color=always "$1"
          }
        '' else ''
          preview() {
            cat "$1"
          }
        ''}
      ''
    ];

    # Atuin configuration
    home-manager.users.yuki.programs.atuin = mkIf cfg.atuin {
      enable = true;
      enableZshIntegration = true;
      enableBashIntegration = true;
      
      settings = {
        auto_sync = true;
        sync_frequency = "5m";
        sync_address = "https://api.atuin.sh";
        search_mode = "fuzzy";
        filter_mode = "global";
        filter_mode_shell_up_key_binding = "session";
        show_preview = true;
        max_preview_height = 4;
        show_help = true;
        exit_mode = "return-original";
        keymap_mode = "emacs";
        word_jump_mode = "word";
        
        # Performance settings
        common_prefix = ["sudo"];
        common_subcommands = ["apt" "cargo" "composer" "dnf" "docker" "git" "go" "ip" "kubectl" "nix" "npm" "pacman" "pnpm" "podman" "port" "systemctl" "tmux" "yarn"];
        
        # Privacy
        secrets_filter = true;
        workspaces = false;
      };
    };

    # VisiData configuration
    home-manager.users.yuki.home.file.".visidatarc" = mkIf cfg.data-analysis {
      text = ''
        # VisiData configuration
        options.regex_flags = 're.IGNORECASE'
        options.clipboard_copy_cmd = 'pbcopy'  # macOS
        options.motd_url = ''  # Disable message of the day
      '';
    };

    # Modern CLI health check script (simplified)
    home-manager.users.yuki.home.file."bin/modern-cli-health" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Modern CLI Tools Health Check
        set -euo pipefail
        
        echo "🚀 Modern CLI Tools Health Check"
        echo "================================="
        echo ""
        
        echo "📁 Navigation Tools:"
      '' + (if cfg.navigation then ''
        command -v eza >/dev/null && echo "✅ eza: Modern ls replacement" || echo "❌ eza: Not found"
        command -v fd >/dev/null && echo "✅ fd: Modern find replacement" || echo "❌ fd: Not found"
      '' else ''
        echo "⚪ Navigation tools: Disabled"
      '') + ''
        
        echo ""
        echo "📄 Content Tools:"
      '' + (if cfg.content then ''
        command -v bat >/dev/null && echo "✅ bat: Modern cat replacement" || echo "❌ bat: Not found"
        command -v rg >/dev/null && echo "✅ rg: Modern grep replacement" || echo "❌ rg: Not found"
      '' else ''
        echo "⚪ Content tools: Disabled"
      '') + ''
        
        echo ""
        echo "⚡ Process Tools:"
      '' + (if cfg.process then ''
        command -v bottom >/dev/null && echo "✅ bottom: Modern top replacement" || echo "❌ bottom: Not found"
        command -v procs >/dev/null && echo "✅ procs: Modern ps replacement" || echo "❌ procs: Not found"
      '' else ''
        echo "⚪ Process tools: Disabled"
      '') + ''
        
        echo ""
        echo "🌳 Git Tools:"
      '' + (if cfg.git then ''
        command -v lazygit >/dev/null && echo "✅ lazygit: Terminal UI for git" || echo "❌ lazygit: Not found"
        command -v delta >/dev/null && echo "✅ delta: Better git diff" || echo "❌ delta: Not found"
      '' else ''
        echo "⚪ Git tools: Disabled"
      '') + ''
        
        echo ""
        echo "📁 File Manager:"
      '' + (if cfg.file-manager then ''
        command -v yazi >/dev/null && echo "✅ yazi: Terminal file manager" || echo "❌ yazi: Not found"
      '' else ''
        echo "⚪ File manager: Disabled"
      '') + ''
        
        echo ""
        echo "💻 System Info:"
      '' + (if cfg.system-info then ''
        command -v fastfetch >/dev/null && echo "✅ fastfetch: System information display" || echo "❌ fastfetch: Not found"
      '' else ''
        echo "⚪ System info: Disabled"
      '') + ''
        
        echo ""
        echo "📊 Data Analysis:"
      '' + (if cfg.data-analysis then ''
        command -v visidata >/dev/null && echo "✅ visidata: Terminal data analysis" || echo "❌ visidata: Not found"
      '' else ''
        echo "⚪ Data analysis: Disabled"
      '') + ''
        
        echo ""
        echo "🔍 Shell Enhancement:"
      '' + (if cfg.atuin then ''
        command -v atuin >/dev/null && echo "✅ atuin: Enhanced shell history" || echo "❌ atuin: Not found"
      '' else ''
        echo "⚪ Atuin: Disabled"
      '') + (if cfg.starship then ''
        command -v starship >/dev/null && echo "✅ starship: Cross-shell prompt" || echo "❌ starship: Not found"
      '' else ''
        echo "⚪ Starship: Disabled"
      '') + (if cfg.zoxide then ''
        command -v zoxide >/dev/null && echo "✅ zoxide: Smart directory jumper" || echo "❌ zoxide: Not found"
      '' else ''
        echo "⚪ Zoxide: Disabled"
      '') + ''
        
        echo ""
        echo "Profile: ${cfg.profile}"
        echo "All checks completed!"
      '';
    };
  };
}
