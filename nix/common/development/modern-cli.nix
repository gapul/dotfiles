# Modern CLI Integration - Unified Advanced Features
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.dotfiles.development.modernCli;
  
  # プラットフォーム検出
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
in
{
  options.dotfiles.development.modernCli = {
    enable = mkEnableOption "Advanced modern CLI tools";
    
    profile = mkOption {
      type = types.enum [ "minimal" "standard" "full" ];
      default = "standard";
      description = "Modern CLI tools profile";
    };
    
    # コア機能制御
    atuin = mkOption {
      type = types.bool;
      default = true;
      description = "Enable atuin shell history management";
    };
    
    zoxide = mkOption {
      type = types.bool;
      default = true;
      description = "Enable zoxide smart directory jumping";
    };
    
    starship = mkOption {
      type = types.bool;
      default = true;
      description = "Enable starship prompt";
    };
    
    modernReplacements = mkOption {
      type = types.bool;
      default = true;
      description = "Enable modern CLI replacements (eza, bat, etc.)";
    };
    
    # 個別ツール制御
    core-replacements = mkEnableOption "Core command replacements (eza, bat, etc.)" // { default = true; };
    search-tools = mkEnableOption "Advanced search tools (ripgrep, fd)" // { default = true; };
    navigation = mkEnableOption "Smart navigation (zoxide)" // { default = true; };
    git-ui = mkEnableOption "Git TUI tools (lazygit)" // { default = true; };
    file-management = mkEnableOption "Modern file managers (yazi)" // { default = true; };
    system-monitoring = mkEnableOption "System monitoring tools (bottom)" // { default = true; };
    history = mkEnableOption "Enhanced history (atuin)" // { default = true; };
    data-analysis = mkEnableOption "Data analysis tools (visidata)" // { default = true; };
    system-info = mkEnableOption "System information display (fastfetch)" // { default = true; };
    fzf-integration = mkEnableOption "Enhanced FZF shell integration" // { default = true; };
  };

  config = mkIf cfg.enable {
    # Core modern CLI tools
    home-manager.users.yuki.home.packages = with pkgs; 
      # Minimal profile packages
      (optionals (cfg.profile == "minimal" || cfg.profile == "standard" || cfg.profile == "full") [
        # Core replacements - 最優先
        (mkIf cfg.core-replacements eza)          # ls replacement
        (mkIf cfg.core-replacements bat)          # cat replacement  
        (mkIf cfg.search-tools ripgrep)           # grep replacement
        (mkIf cfg.search-tools fd)                # find replacement
        (mkIf cfg.navigation zoxide)              # cd replacement
        fzf                                       # Fuzzy finder - 全プロファイルで必須
      ]) ++
      
      # Standard profile additions
      (optionals (cfg.profile == "standard" || cfg.profile == "full") [
        (mkIf cfg.git-ui lazygit)                 # Git TUI
        (mkIf cfg.file-management yazi)           # File manager
        (mkIf cfg.system-monitoring bottom)       # System monitor
        delta                                     # Modern diff replacement
        hyperfine                                 # Command-line benchmarking
        dust                                      # Modern du replacement
        procs                                     # Modern ps replacement
      ]) ++
      
      # Full profile additions
      (optionals (cfg.profile == "full") [
        (mkIf cfg.history atuin)                  # Command history
        duf                                       # df replacement
        gdu                                       # du replacement  
        (mkIf cfg.system-info fastfetch)          # system info
        bandwhich                                 # Network utilization by process
        tokei                                     # Code statistics
        sd                                        # Modern sed replacement
        choose                                    # Human-friendly cut/awk alternative
        # Data analysis tools
        (mkIf cfg.data-analysis visidata)         # Interactive data analysis
        (mkIf cfg.data-analysis miller)           # Data processing with mlr
      ]);

    # Atuin configuration
    home-manager.users.yuki.programs.atuin = mkIf cfg.atuin {
      enable = true;
      
      settings = {
        # Sync settings
        auto_sync = true;
        sync_frequency = "10m";
        sync_address = "https://api.atuin.sh";
        
        # Search settings
        search_mode = "fuzzy";
        search_mode_shell_up_key_binding = "fuzzy";
        filter_mode = "global";
        filter_mode_shell_up_key_binding = "session";
        
        # Display settings
        show_preview = true;
        max_preview_height = 4;
        show_help = true;
        exit_mode = "return-original";
        
        # History settings
        history_filter = [
          "^ls$"
          "^cd$"
          "^cd \\.\\.?$"
          "^pwd$"
          "^exit$"
          "^clear$"
          "^history$"
        ];
        
        # Privacy settings
        secrets_filter = true;
        
        # Performance settings
        style = "compact";
        inline_height = 25;
        
        # Data settings
        update_check = false;
      };
      
      # Keybindings
      enableZshIntegration = true;
      enableBashIntegration = true;
    };

    # Zoxide configuration
    home-manager.users.yuki.programs.zoxide = mkIf cfg.zoxide {
      enable = true;
      enableZshIntegration = true;
      enableBashIntegration = true;
      
      options = [
        "--cmd cd"  # Use 'cd' command instead of 'z'
      ];
    };

    # Starship prompt configuration
    home-manager.users.yuki.programs.starship = mkIf cfg.starship {
      enable = true;
      enableZshIntegration = true;
      enableBashIntegration = true;
      
      settings = {
        # Prompt format
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
          "$docker_context"
          "$kubernetes"
          "$aws"
          "$nix_shell"
          "$memory_usage"
          "$cmd_duration"
          "$line_break"
          "$character"
        ];
        
        # Character configuration
        character = {
          success_symbol = "[❯](bold green)";
          error_symbol = "[❯](bold red)";
          vicmd_symbol = "[❮](bold yellow)";
        };
        
        # Directory configuration
        directory = {
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
        };
        
        python = {
          symbol = " ";
          detect_extensions = ["py"];
        };
        
        rust = {
          symbol = " ";
          detect_extensions = ["rs"];
        };
        
        golang = {
          symbol = " ";
          detect_extensions = ["go"];
        };
        
        # Docker and Kubernetes
        docker_context = {
          symbol = " ";
          only_with_files = true;
        };
        
        kubernetes = {
          symbol = "☸ ";
          disabled = false;
        };
        
        # Cloud providers
        aws = {
          symbol = "☁️  ";
          disabled = false;
        };
        
        # Nix shell
        nix_shell = {
          symbol = " ";
          format = "via [$symbol$state( \\($name\\))]($style) ";
          impure_msg = "[impure shell](bold red)";
          pure_msg = "[pure shell](bold green)";
          unknown_msg = "[unknown shell](bold yellow)";
        };
        
        # Performance monitoring
        cmd_duration = {
          min_time = 2_000;
          format = "took [$duration](bold yellow)";
        };
        
        memory_usage = {
          disabled = false;
          threshold = 70;
          symbol = " ";
          style = "bold dimmed green";
        };
      };
    };

    # Enhanced shell aliases for modern tools
    home-manager.users.yuki.programs.zsh = {
      shellAliases = mkMerge [
        # Core command replacements
        (mkIf cfg.core-replacements {
          ls = "eza --color=auto --icons --group-directories-first";
          ll = "eza -la --color=auto --icons --group-directories-first --git";
          la = "eza -la --color=auto --icons --group-directories-first --git";
          lt = "eza --tree --level=2 --color=auto --icons";
          cat = "bat --style=auto";
          tree = "eza --tree --icons";
        })
        
        (mkIf cfg.search-tools {
          grep = "rg";
          find = "fd";
        })
        
        (mkIf cfg.system-monitoring {
          htop = "btm";
          top = "btm";
        })
        
        # Disk usage
        (mkIf (cfg.profile == "full") {
          df = "duf";
          du = "gdu";
        })
        
        # System info
        (mkIf cfg.system-info {
          neofetch = "fastfetch";
          sysinfo = "fastfetch";
          info = "fastfetch";
        })
        
        # Data analysis
        (mkIf cfg.data-analysis {
          vd = "visidata";
          data = "visidata";
          analyze = "visidata";
        })
        
        (mkIf cfg.atuin {
          # Atuin shortcuts
          history = "atuin search";
          hist = "atuin search";
          stats = "atuin stats";
          
          # History navigation
          h = "atuin search";
          hs = "atuin search --interactive";
          hh = "atuin history last";
        })
        
        (mkIf cfg.zoxide {
          # Zoxide shortcuts
          j = "z";
          zi = "zi";  # Interactive mode
          zq = "zoxide query";
          zr = "zoxide remove";
        })
        
        # Git with delta
        (mkIf cfg.git-ui {
          git-diff = "git diff --color-moved --color-moved-ws=allow-indentation-change";
        })
        
        # Search and navigation
        (mkIf cfg.search-tools {
          search = "rg --smart-case --follow --hidden";
          files = "fd --type f --hidden --follow";
          dirs = "fd --type d --hidden --follow";
        })
      ];
      
      # Enhanced shell integration
      initExtra = mkMerge [
        (mkIf cfg.navigation ''
          # Zoxide integration
          eval "$(zoxide init zsh)"
          alias cd="z"
          alias cdi="zi"  # Interactive selection
        '')
        
        (mkIf cfg.fzf-integration ''
          # Enhanced FZF integration with modern tools
          
          # Load FZF key bindings if available
          if [[ -f /usr/share/fzf/key-bindings.zsh ]]; then
            source /usr/share/fzf/key-bindings.zsh
          elif [[ -f ~/.fzf/shell/key-bindings.zsh ]]; then
            source ~/.fzf/shell/key-bindings.zsh
          fi
          
          if [[ -f /usr/share/fzf/completion.zsh ]]; then
            source /usr/share/fzf/completion.zsh
          elif [[ -f ~/.fzf/shell/completion.zsh ]]; then
            source ~/.fzf/shell/completion.zsh
          fi
          
          # Enhanced file search function
          fzf-file-widget() {
            local cmd="fd --type f --hidden --follow --exclude .git"
            local selected=$(eval "$cmd" | fzf \
              --height 60% \
              --layout=reverse \
              --border \
              --preview 'bat --style=numbers --color=always --line-range :500 {}' \
              --preview-window=right:50%:wrap \
              --bind 'ctrl-/:toggle-preview' \
              --bind 'ctrl-y:execute-silent(echo {} | pbcopy)+abort' \
              --header 'CTRL-Y: copy path, CTRL-/: toggle preview')
            
            if [[ -n "$selected" ]]; then
              LBUFFER="${LBUFFER}${selected}"
              zle reset-prompt
            fi
          }
          
          # Enhanced directory navigation
          fzf-cd-widget() {
            local cmd="fd --type d --hidden --follow --exclude .git"
            local dir=$(eval "$cmd" | fzf \
              --height 60% \
              --layout=reverse \
              --border \
              --preview 'eza --tree --level=2 --color=always --icons {} 2>/dev/null || ls -la {}' \
              --preview-window=right:50%:wrap \
              --bind 'ctrl-/:toggle-preview' \
              --header 'Select directory')
            
            if [[ -n "$dir" ]]; then
              cd "$dir"
              zle reset-prompt
            fi
          }
          
          # Git file browser
          fzf-git-files() {
            if ! git rev-parse --git-dir > /dev/null 2>&1; then
              echo "Not in a git repository"
              return 1
            fi
            
            local selected=$(git ls-files | fzf \
              --height 60% \
              --layout=reverse \
              --border \
              --preview 'bat --style=numbers --color=always {} 2>/dev/null || cat {}' \
              --preview-window=right:50%:wrap \
              --bind 'ctrl-/:toggle-preview' \
              --header 'Select git-tracked file')
            
            if [[ -n "$selected" ]]; then
              LBUFFER="${LBUFFER}${selected}"
              zle reset-prompt
            fi
          }
          
          # Process killer
          fzf-kill-process() {
            local pid=$(ps -eo pid,ppid,user,comm --no-headers | fzf \
              --height 60% \
              --layout=reverse \
              --border \
              --header 'Select process to kill' \
              --preview 'ps -p {1} -o pid,ppid,user,comm,cmd' \
              --preview-window=down:3:wrap | awk '{print $1}')
            
            if [[ -n "$pid" ]]; then
              echo "Killing process $pid"
              kill -TERM "$pid"
              zle reset-prompt
            fi
          }
          
          # Environment variable browser
          fzf-env-vars() {
            local selected=$(env | sort | fzf \
              --height 60% \
              --layout=reverse \
              --border \
              --header 'Select environment variable' \
              --preview 'echo {}' \
              --preview-window=down:3:wrap)
            
            if [[ -n "$selected" ]]; then
              local var_name="${selected%%=*}"
              LBUFFER="${LBUFFER}$var_name"
              zle reset-prompt
            fi
          }
          
          # Register custom widgets
          zle -N fzf-file-widget
          zle -N fzf-cd-widget
          zle -N fzf-git-files
          zle -N fzf-kill-process
          zle -N fzf-env-vars
          
          # Key bindings (override defaults with enhanced versions)
          bindkey '^T' fzf-file-widget
          bindkey '\ec' fzf-cd-widget
          bindkey '^G^F' fzf-git-files
          bindkey '^X^K' fzf-kill-process  
          bindkey '^X^E' fzf-env-vars
          
          # Convenience aliases
          alias ff='fzf-file-widget'
          alias fd-dir='fzf-cd-widget'
          alias fzf-git='fzf-git-files'
          alias fkill='fzf-kill-process'
          alias fenv='fzf-env-vars'
        '')
      ];
    };

    # Platform-specific optimizations
    home-manager.users.yuki.home.sessionVariables = mkMerge [
      # Eza configuration
      (mkIf cfg.core-replacements {
        EZA_COLORS = "di=34:ln=35:so=32:pi=33:ex=31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43";
        EZA_ICON_SPACING = "2";
      })
      
      # Ripgrep configuration  
      (mkIf cfg.search-tools {
        RIPGREP_CONFIG_PATH = "$HOME/.config/ripgrep/config";
      })
      
      # Yazi integration
      (mkIf cfg.file-management {
        YAZI_FILE_ONE = "${pkgs.file}/bin/file";
      })
      
      # Atuin
      (mkIf cfg.atuin {
        ATUIN_NOBIND = "true";  # We handle keybindings ourselves
      })
      
      # Bat configuration
      (mkIf cfg.core-replacements {
        BAT_THEME = "Catppuccin-macchiato";
        BAT_STYLE = "numbers,changes,header";
      })
      
      # Enhanced FZF configuration
      (mkIf cfg.fzf-integration {
        FZF_DEFAULT_COMMAND = "fd --type f --hidden --follow --exclude .git";
        FZF_DEFAULT_OPTS = lib.concatStringsSep " " [
          "--height 60%"
          "--layout=reverse"
          "--border"
          "--preview 'bat --style=numbers --color=always --line-range :500 {}'"
          "--preview-window=right:50%:wrap"
          "--bind 'ctrl-/:toggle-preview'"
          "--bind 'ctrl-u:preview-up'"
          "--bind 'ctrl-d:preview-down'"
          "--bind 'ctrl-y:execute-silent(echo {} | pbcopy)'"
          "--color=fg:#cdd6f4,bg:#1e1e2e,hl:#f38ba8"
          "--color=fg+:#cdd6f4,bg+:#313244,hl+:#f38ba8"
          "--color=info:#cba6f7,prompt:#cba6f7,pointer:#f5e0dc"
          "--color=marker:#f5e0dc,spinner:#f5e0dc,header:#f38ba8"
        ];
        FZF_CTRL_T_COMMAND = "fd --type f --hidden --follow --exclude .git";
        FZF_CTRL_T_OPTS = "--preview 'bat --style=numbers --color=always --line-range :500 {}'";
        FZF_ALT_C_COMMAND = "fd --type d --hidden --follow --exclude .git";
        FZF_ALT_C_OPTS = "--preview 'eza --tree --level=2 --color=always --icons {} 2>/dev/null || ls -la {}'";
        FZF_CTRL_R_OPTS = "--preview 'echo {}' --preview-window down:3:hidden:wrap --bind 'ctrl-/:toggle-preview'";
      })
      
      # Fallback FZF configuration for when integration is disabled
      (mkIf (!cfg.fzf-integration) {
        FZF_DEFAULT_COMMAND = "fd --type f --hidden --follow --exclude .git";
        FZF_DEFAULT_OPTS = "--height 40% --layout=reverse --border";
      })
      
      # Delta configuration
      (mkIf cfg.git-ui {
        DELTA_FEATURES = "+side-by-side";
      })
      
      # Less configuration for better paging
      {
        LESS = "-R --use-color -Dd+r$Du+b$";
        LESSOPEN = "|${pkgs.lesspipe}/bin/lesspipe.sh %s";
      }
      
      # VisiData configuration
      (mkIf cfg.data-analysis {
        VISIDATA_DIR = "$HOME/.config/visidata";
        VD_EDITOR = "nvim";
      })
      
      # FastFetch configuration
      (mkIf cfg.system-info {
        FASTFETCH_CONFIG_DIR = "$HOME/.config/fastfetch";
      })
    ];

    # Ripgrep configuration file
    home-manager.users.yuki.home.file.".config/ripgrep/config" = {
      text = ''
        # Global ripgrep configuration
        
        # Smart case search
        --smart-case
        
        # Show line numbers
        --line-number
        
        # Follow symlinks
        --follow
        
        # Search hidden files
        --hidden
        
        # Ignore patterns
        --glob=!.git/*
        --glob=!node_modules/*
        --glob=!target/*
        --glob=!dist/*
        --glob=!build/*
        --glob=!*.lock
        --glob=!*.log
        
        # File type associations
        --type-add=web:*.{html,css,scss,sass,js,jsx,ts,tsx,vue,svelte}
        --type-add=config:*.{json,yaml,yml,toml,ini,conf,cfg}
        --type-add=docker:*{Dockerfile,docker-compose.yml}
        --type-add=nix:*.nix
      '';
    };

    # VisiData configuration
    home-manager.users.yuki.home.file.\".visidatarc\" = mkIf cfg.data-analysis {
      text = ''
        # VisiData configuration for enhanced data analysis
        
        # Theme and appearance (Catppuccin-inspired)
        options.color_default = 'white on black'
        options.color_key_col = 'bold white on 24 blue'
        options.color_selected_row = 'black on 215 yellow'
        options.color_current_col = 'bold black on 159 cyan'
        options.color_current_row = 'reverse'
        
        # Performance settings
        options.min_memory_mb = 100
        options.encoding = 'utf-8'
        options.encoding_errors = 'replace'
        options.max_rows = 1000000
        
        # Data handling
        options.csv_delimiter = ','
        options.csv_quotechar = '"'
        options.json_indent = 2
        options.fixed_rows = 1000
        options.incr_base = 1.0
        
        # Display settings
        options.disp_column_sep = ' │ '
        options.disp_more_left = '◀'
        options.disp_more_right = '▶'
        options.disp_truncator = '…'
        options.default_width = 20
        options.wrap = False
        
        # Graph and plotting
        options.plot_colors = ['red', 'blue', 'green', 'yellow', 'cyan', 'magenta', 'white']
        options.histogram_bins = 50
        options.graph_type = 'line'
        
        # Save settings
        options.save_filetype = 'csv'
        options.confirm_overwrite = False
        options.undo = True
        
        # Modern keybindings (Vim-like)
        unbindkey('q')  # Don't quit on 'q'
        bindkey('ENTER', 'dive-row')
        bindkey('Space', 'select-row')
        bindkey('u', 'undo')
        bindkey('U', 'redo') 
        bindkey('/', 'search-forward')
        bindkey('?', 'search-backward')
        bindkey('n', 'search-next')
        bindkey('N', 'search-prev')
        bindkey('gh', 'go-leftmost')
        bindkey('gl', 'go-rightmost') 
        bindkey('gg', 'go-top')
        bindkey('G', 'go-bottom')
        
        # Data type detection
        options.type_float = 'float'
        options.type_int = 'int'
        options.type_currency = 'currency'
        options.type_date = 'date'
        options.null_value = ''
        
        # Format options
        options.disp_float_fmt = '{:.6g}'
        options.disp_int_fmt = '{:d}'
        options.disp_currency_fmt = '${:,.02f}'
        options.date_format = '%Y-%m-%d'
        options.datetime_format = '%Y-%m-%d %H:%M:%S'
        
        # Frequency table settings
        options.histogram_even = False
        options.describe_aggrs = 'mean stdev min max median mode count nulls'
        
        # Advanced features
        options.regex_flags = 're.IGNORECASE'
        options.clipboard_copy_cmd = 'pbcopy'  # macOS
        options.motd_url = ''  # Disable message of the day
      '';
    };

    # FastFetch configuration for system information
    home-manager.users.yuki.home.file.\".config/fastfetch/config.jsonc\" = mkIf cfg.system-info {
      text = ''
        {
          // FastFetch configuration for modern system info display
          "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
          "logo": {
            "source": "auto",
            "type": "auto"
          },
          "display": {
            "separator": " → ",
            "color": {
              "keys": "blue",
              "title": "blue"
            }
          },
          "modules": [
            {
              "type": "title",
              "color": {
                "user": "blue",
                "at": "white", 
                "host": "green"
              }
            },
            "separator",
            "os",
            "host",
            "kernel",
            "uptime",
            "packages",
            "shell",
            {
              "type": "display",
              "compactType": "original"
            },
            "de",
            "wm",
            "wmtheme",
            "theme",
            "icons",
            "font",
            "cursor",
            "terminal",
            "terminalfont",
            "cpu",
            "gpu",
            "memory",
            "swap",
            "disk",
            "localip",
            "battery",
            "poweradapter",
            "locale",
            "break",
            {
              "type": "colors",
              "paddingLeft": 2,
              "symbol": "circle"
            }
          ]
        }
      '';
    };

    # Modern CLI integration scripts
    home-manager.users.yuki.home.file."bin/modern-cli-setup" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Modern CLI Tools Setup and Configuration
        set -euo pipefail
        
        echo "🚀 Modern CLI Tools Setup"
        echo "========================"
        
        # Atuin setup
        ${if cfg.atuin then ''
          echo ""
          echo "📈 Setting up Atuin..."
          if command -v atuin &> /dev/null; then
            # Import existing shell history if not done
            if [[ ! -f "$HOME/.local/share/atuin/imported" ]]; then
              echo "📚 Importing existing shell history..."
              atuin import auto
              touch "$HOME/.local/share/atuin/imported"
              echo "✅ History import completed"
            else
              echo "✅ Atuin already configured"
            fi
            
            # Register for sync (optional)
            if [[ -z "''${ATUIN_SESSION:-}" ]]; then
              echo "💡 To sync history across devices:"
              echo "   1. Run: atuin register"
              echo "   2. Run: atuin login"
              echo "   3. Run: atuin sync"
            fi
          else
            echo "❌ Atuin not found"
          fi
        '' else ''
          echo "📈 Atuin: Disabled"
        ''}
        
        # Zoxide setup
        ${if cfg.zoxide then ''
          echo ""
          echo "📁 Setting up Zoxide..."
          if command -v zoxide &> /dev/null; then
            echo "✅ Zoxide is available"
            echo "💡 Use 'cd' for smart navigation, 'zi' for interactive selection"
          else
            echo "❌ Zoxide not found"
          fi
        '' else ''
          echo "📁 Zoxide: Disabled"
        ''}
        
        # VisiData setup
        ${if cfg.data-analysis then ''
          echo ""
          echo "📊 Setting up VisiData..."
          if command -v visidata &> /dev/null; then
            echo "✅ VisiData is available"
            echo "💡 Use 'vd <file>' to analyze data, 'data <file>' for quick access"
            
            # Create VisiData config directory
            mkdir -p "$HOME/.config/visidata"
            echo "✅ VisiData configuration directory created"
          else
            echo "❌ VisiData not found"
          fi
        '' else ''
          echo "📊 VisiData: Disabled"
        ''}
        
        # FastFetch setup
        ${if cfg.system-info then ''
          echo ""
          echo "💻 Setting up FastFetch..."
          if command -v fastfetch &> /dev/null; then
            echo "✅ FastFetch is available"
            echo "💡 Use 'fastfetch' or 'info' to display system information"
            
            # Create FastFetch config directory
            mkdir -p "$HOME/.config/fastfetch"
            echo "✅ FastFetch configuration directory created"
          else
            echo "❌ FastFetch not found"
          fi
        '' else ''
          echo "💻 FastFetch: Disabled"
        ''}
        
        # Create useful aliases script
        echo ""
        echo "⚙️  Creating modern CLI aliases..."
        
        cat > "$HOME/bin/cli-shortcuts" << 'EOF'
        #!/usr/bin/env bash
        # Modern CLI shortcuts and workflows
        
        # Quick search functions
        search_code() {
          rg --type web --type rust --type python --type config "$1"
        }
        
        search_files() {
          fd --type f "$1" | fzf --preview 'bat --style=numbers --color=always {}'
        }
        
        search_dirs() {
          fd --type d "$1" | fzf --preview 'eza --tree --level=2 {}'
        }
        
        # Quick project navigation
        project_jump() {
          local project_dir
          project_dir=$(fd --type d --max-depth 3 "\.git$" ~/Projects ~/Development ~/Code 2>/dev/null | sed 's/\.git$//' | fzf --preview 'eza --tree --level=1 {}')
          if [[ -n "$project_dir" ]]; then
            cd "$project_dir"
          fi
        }
        
        # Git with modern tools
        git_status_modern() {
          echo "📊 Git Status (Modern View)"
          echo "=========================="
          git status --short | bat --language=diff
          echo ""
          echo "📝 Recent Commits:"
          git log --oneline -10 | bat --language=gitlog
        }
        
        # System monitoring
        system_overview() {
          echo "💻 System Overview"
          echo "=================="
          echo ""
          echo "🔧 Processes:"
          procs --tree | head -20
          echo ""
          echo "💾 Disk Usage:"
          dust -d 1 $HOME | head -10
          echo ""
          echo "🌐 Network:"
          bandwhich --no-resolve &
          sleep 3
          kill $!
        }
        
        # Data analysis helper
        analyze_data() {
          local file="$1"
          if [[ -z "$file" ]]; then
            echo "Usage: analyze_data <file>"
            echo "Supported formats: CSV, JSON, TSV, Excel"
            return 1
          fi
          
          if [[ ! -f "$file" ]]; then
            echo "Error: File '$file' not found"
            return 1
          fi
          
          echo "📊 Quick Data Analysis: $file"
          echo "============================="
          
          # File info
          echo "📁 File size: $(ls -lh "$file" | awk '{print $5}')"
          echo "📅 Modified: $(ls -l "$file" | awk '{print $6, $7, $8}')"
          
          # Preview based on file type
          case "${file##*.}" in
            csv|CSV)
              echo ""
              echo "📋 CSV Preview (first 5 rows):"
              head -5 "$file" | column -t -s,
              echo ""
              echo "📊 Column count: $(head -1 "$file" | tr ',' '\n' | wc -l)"
              echo "📏 Row count: $(wc -l < "$file")"
              ;;
            json|JSON)
              echo ""
              echo "📋 JSON Structure:"
              jq 'keys' "$file" 2>/dev/null || echo "Invalid JSON format"
              ;;
            *)
              echo ""
              echo "📋 File preview:"
              head -10 "$file"
              ;;
          esac
          
          echo ""
          echo "💡 Open with VisiData: vd '$file'"
        }
        
        # System info display
        show_system_info() {
          if command -v fastfetch &> /dev/null; then
            fastfetch
          else
            echo "💻 Basic System Information"
            echo "=========================="
            echo "OS: $(uname -s)"
            echo "Kernel: $(uname -r)"
            echo "Architecture: $(uname -m)"
            echo "Hostname: $(hostname)"
            echo "User: $USER"
            echo "Shell: $SHELL"
            echo "Uptime: $(uptime | awk '{print $3, $4}' | sed 's/,//')"
          fi
        }
        
        # Export functions
        export -f search_code search_files search_dirs project_jump git_status_modern system_overview analyze_data show_system_info
        EOF
        
        chmod +x "$HOME/bin/cli-shortcuts"
        
        echo ""
        echo "✅ Modern CLI setup completed!"
        echo ""
        echo "🎯 Available Commands:"
        echo "  Profile: ${cfg.profile}"
        echo "  Core: eza, bat, rg, fd, fzf"
        ${if cfg.profile == "standard" || cfg.profile == "full" then ''
          echo "  Standard: lazygit, yazi, bottom, delta, dust, procs"
        '' else ""}
        ${if cfg.profile == "full" then ''
          echo "  Full: atuin, duf, gdu"
        '' else ""}
        ${if cfg.system-info then ''
          echo "  System Info: fastfetch"
        '' else ""}
        ${if cfg.data-analysis then ''
          echo "  Data Analysis: visidata, miller"
        '' else ""}
        echo "  Shell: zoxide (navigation), starship (prompt)"
        echo "  Scripts: cli-shortcuts (additional functions)"
        echo ""
        echo "📖 Quick Tips:"
        echo "  • Use 'll' for detailed file listing"
        echo "  • Use 'h <term>' to search command history (atuin)"
        echo "  • Use 'z <partial>' for smart directory jumping"
        echo "  • Use 'search <term>' for code search"
        echo "  • Use 'yazi' for modern file management"
        ${if cfg.data-analysis then ''
          echo "  • Use 'vd <file>' for interactive data analysis"
        '' else ""}
        ${if cfg.system-info then ''
          echo "  • Use 'info' or 'fastfetch' for system information"
        '' else ""}
        ${if cfg.fzf-integration then ''
          echo "  • Enhanced FZF: Ctrl+T (files), Alt+C (dirs), Ctrl+R (history)"
          echo "  • Git FZF: Ctrl+G,F (git files), fkill (process killer)"
        '' else ""}
        echo "  • Use Ctrl+R for enhanced history search"
      '';
    };

    # Health check for modern CLI tools
    home-manager.users.yuki.home.file."bin/modern-cli-health" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        
        echo "🔧 Modern CLI Tools Health Check"
        echo "================================"
        
        ISSUES=0
        
        # Check each tool based on profile and enabled features
        tools=(
          ${if cfg.core-replacements then ''"eza:Modern ls" "bat:Modern cat"'' else ""}
          ${if cfg.search-tools then ''"rg:Ripgrep" "fd:Modern find"'' else ""}
          ${if cfg.navigation then ''"zoxide:Smart navigation"'' else ""}
          ${if cfg.git-ui then ''"lazygit:Git TUI" "delta:Git diff"'' else ""}
          ${if cfg.file-management then ''"yazi:File manager"'' else ""}
          ${if cfg.system-monitoring then ''"btm:Bottom"'' else ""}
          ${if cfg.history then ''"atuin:Shell history"'' else ""}
          ${if cfg.starship then ''"starship:Prompt"'' else ""}
          "fzf:Fuzzy finder"  # Always included
          ${if cfg.profile == "standard" || cfg.profile == "full" then ''"dust:Modern du" "procs:Modern ps"'' else ""}
          ${if cfg.profile == "full" then ''"duf:Modern df" "gdu:Modern du"'' else ""}
          ${if cfg.system-info then ''"fastfetch:System info"'' else ""}
          ${if cfg.data-analysis then ''"visidata:Data analysis" "miller:Data processing"'' else ""}
          ${if cfg.fzf-integration then ''"fzf:Fuzzy finder (enhanced)"'' else ""}
        )
        
        for tool_info in "''${tools[@]}"; do
          if [[ -n "$tool_info" ]]; then
            tool=$(echo "$tool_info" | cut -d: -f1)
            desc=$(echo "$tool_info" | cut -d: -f2)
            
            if command -v "$tool" &> /dev/null; then
              echo "✅ $desc ($tool): Available"
            else
              echo "❌ $desc ($tool): Not found"
              ((ISSUES++))
            fi
          fi
        done
        
        # Check atuin specific health
        ${if cfg.atuin then ''
          echo ""
          echo "📈 Atuin Status:"
          if command -v atuin &> /dev/null; then
            local_entries=$(atuin stats | grep "Total commands" | awk '{print $3}' || echo "0")
            echo "  📊 Local history entries: $local_entries"
            
            if atuin status &> /dev/null; then
              echo "  ✅ Sync: Configured"
            else
              echo "  ⚪ Sync: Not configured (optional)"
            fi
          fi
        '' else ''
          echo ""
          echo "📈 Atuin: Disabled"
        ''}
        
        # Check zoxide database
        ${if cfg.zoxide then ''
          echo ""
          echo "📁 Zoxide Status:"
          if command -v zoxide &> /dev/null; then
            local db_entries=$(zoxide query --list | wc -l | tr -d ' ')
            echo "  📊 Directory database entries: $db_entries"
            echo "  💡 Use 'zoxide add <path>' to add frequently used directories"
          fi
        '' else ''
          echo ""
          echo "📁 Zoxide: Disabled"
        ''}
        
        # Configuration files check
        echo ""
        echo "⚙️  Configuration:"
        config_files=(
          "$HOME/.config/ripgrep/config:Ripgrep config"
          "$HOME/.config/atuin/config.toml:Atuin config"
          "$HOME/.config/starship.toml:Starship config"
        )
        
        for config_info in "''${config_files[@]}"; do
          file=$(echo "$config_info" | cut -d: -f1)
          desc=$(echo "$config_info" | cut -d: -f2)
          
          if [[ -f "$file" ]]; then
            echo "  ✅ $desc: Found"
          else
            echo "  ⚪ $desc: Using defaults"
          fi
        done
        
        # Summary
        echo ""
        echo "📊 Summary:"
        if [[ $ISSUES -eq 0 ]]; then
          echo "  ✅ All modern CLI tools operational"
        else
          echo "  ⚠️  $ISSUES issues detected"
        fi
        
        echo ""
        echo "🚀 Next Steps:"
        echo "  • Run 'modern-cli-setup' for initial configuration"
        echo "  • Source your shell config or restart terminal"
        echo "  • Try 'll', 'h <term>', or 'search <pattern>'"
      '';
    };
  };
}