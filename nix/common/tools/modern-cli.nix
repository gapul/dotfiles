{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modern-cli;
  
  # プラットフォーム検出
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
in
{
  imports = [
    ./neovim-modern-cli.nix
  ];
  options.modern-cli = {
    enable = mkEnableOption "Modern CLI/TUI tools";
    
    profile = mkOption {
      type = types.enum [ "minimal" "standard" "full" ];
      default = "standard";
      description = "Modern CLI tools profile";
    };
    
    # 個別ツール制御
    core-replacements = mkEnableOption "Core command replacements (eza, bat, etc.)" // { default = true; };
    search-tools = mkEnableOption "Advanced search tools (ripgrep, fd)" // { default = true; };
    navigation = mkEnableOption "Smart navigation (zoxide)" // { default = true; };
    git-ui = mkEnableOption "Git TUI tools (lazygit)" // { default = true; };
    file-management = mkEnableOption "Modern file managers (yazi)" // { default = true; };
    system-monitoring = mkEnableOption "System monitoring tools (bottom)" // { default = true; };
    history = mkEnableOption "Enhanced history (atuin)" // { default = false; }; # 初期は無効
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
      ]) ++
      
      # Standard profile additions
      (optionals (cfg.profile == "standard" || cfg.profile == "full") [
        (mkIf cfg.git-ui lazygit)                 # Git TUI
        (mkIf cfg.file-management yazi)           # File manager
        (mkIf cfg.system-monitoring bottom)       # System monitor
      ]) ++
      
      # Full profile additions
      (optionals (cfg.profile == "full") [
        (mkIf cfg.history atuin)                  # Command history
        duf                                       # df replacement
        gdu                                       # du replacement  
        fastfetch                                 # system info
        # Development tools
        (mkIf (cfg.git-ui && isDarwin) delta) # Better git diff
      ]);

    # Shell integration and aliases
    home-manager.users.yuki.programs.zsh = mkIf cfg.core-replacements {
      shellAliases = {
        # Core command replacements
        ls = mkIf cfg.core-replacements "eza --color=auto --icons --group-directories-first";
        ll = mkIf cfg.core-replacements "eza -la --color=auto --icons --group-directories-first --git";
        lt = mkIf cfg.core-replacements "eza --tree --level=2 --color=auto --icons";
        cat = mkIf cfg.core-replacements "bat --style=auto";
        grep = mkIf cfg.search-tools "rg";
        find = mkIf cfg.search-tools "fd";
        
        # System monitoring
        htop = mkIf cfg.system-monitoring "btm";
        top = mkIf cfg.system-monitoring "btm";
        
        # Disk usage
        df = mkIf (cfg.profile == "full") "duf";
        du = mkIf (cfg.profile == "full") "gdu";
        
        # System info
        neofetch = mkIf (cfg.profile == "full") "fastfetch";
      };
      
      # Zoxide integration (smart cd)
      initExtra = mkIf cfg.navigation ''
        # Zoxide integration
        eval "$(zoxide init zsh)"
        alias cd="z"
        alias cdi="zi"  # Interactive selection
      '';
    };

    # Atuin configuration (if enabled)
    home-manager.users.yuki.programs.atuin = mkIf cfg.history {
      enable = true;
      settings = {
        auto_sync = true;
        sync_frequency = "1h";
        search_mode = "fuzzy";
        style = "compact";
        show_help = false;
        exit_mode = "return-original";
        # プライバシー考慮
        sync_address = "https://api.atuin.sh";
        keymap_mode = "emacs";  # Zshデフォルトに合わせる
      };
    };

    # Yazi configuration
    home-manager.users.yuki.programs.yazi = mkIf cfg.file-management {
      enable = true;
      enableZshIntegration = true;
      settings = {
        manager = {
          show_hidden = true;
          sort_by = "modified";
          sort_reverse = true;
          linemode = "size";
        };
        preview = {
          wrap = "yes";
          tab_size = 2;
          max_width = 600;
          max_height = 900;
        };
        opener = mkIf isDarwin {
          edit = [
            { run = "nvim \"$@\""; block = true; }
          ];
          open = [
            { run = "open \"$@\""; }
          ];
          reveal = [
            { run = "open -R \"$@\""; }
          ];
        };
      };
    };

    # Git integration
    home-manager.users.yuki.programs.git = mkIf cfg.git-ui {
      delta.enable = mkDefault true;
    };

    # Modern CLI tools configuration files
    home-manager.users.yuki.home.file = {
      # Bottom (system monitor) configuration
      ".config/bottom/bottom.toml" = mkIf cfg.system-monitoring {
        text = ''
          # Bottom configuration for system monitoring
          [colors]
          table_header_color = "Blue"
          all_entry_color = "White"
          avg_entry_color = "Red"
          cpu_core_colors = ["LightMagenta", "LightYellow", "LightCyan", "LightGreen", "LightBlue", "LightRed", "Cyan", "Green", "Blue", "Red"]
          ram_color = "LightMagenta"
          swap_color = "LightYellow"
          rx_color = "LightCyan"
          tx_color = "LightGreen"
          widget_title_color = "Gray"
          border_color = "Gray"
          highlighted_border_color = "LightBlue"
          text_color = "Gray"
          graph_color = "Gray"
          cursor_color = "Red"
          selected_text_color = "Black"
          selected_bg_color = "LightBlue"
          high_battery_color = "green"
          medium_battery_color = "yellow"
          low_battery_color = "red"

          [flags]
          dot_marker = true
          temperature_type = "celsius"
          rate = 1000
          left_legend = true
          current_usage = true
          group_processes = true
          case_sensitive = false
          whole_word = false
          regex = false
          basic = false
          use_old_network_legend = false
          hide_avg_cpu = false
          battery = true
        '';
      };

      # Bat configuration for syntax highlighting
      ".config/bat/config" = mkIf cfg.core-replacements {
        text = ''
          # Bat configuration
          --theme="Catppuccin-macchiato"
          --style="numbers,changes,header"
          --wrap=auto
          --pager="less -FR"
          --map-syntax "*.conf:INI"
          --map-syntax ".ignore:Git Ignore"
        '';
      };

      # Yazi theme integration
      ".config/yazi/theme.toml" = mkIf cfg.file-management {
        text = ''
          # Yazi theme configuration (Catppuccin integration)
          [flavor]
          use = "catppuccin-macchiato"
          
          [manager]
          cwd = { fg = "blue", bold = true }
          hovered = { bg = "surface0", bold = true }
          preview_hovered = { bg = "surface0" }
          
          [status]
          separator_open = ""
          separator_close = ""
          mode_normal = { fg = "base", bg = "blue", bold = true }
          mode_select = { fg = "base", bg = "green", bold = true }
          mode_unset = { fg = "base", bg = "flamingo", bold = true }
          
          [input]
          border = { fg = "blue" }
          title = { fg = "lavender" }
          value = { fg = "text" }
          selected = { reversed = true }
          
          [select]
          border = { fg = "blue" }
          active = { fg = "peach" }
          inactive = { fg = "surface2" }
          
          [tasks]
          border = { fg = "blue" }
          title = { fg = "lavender" }
          hovered = { fg = "peach" }
          
          [which]
          cols = 3
          mask = { bg = "surface0" }
          cand = { fg = "blue" }
          rest = { fg = "overlay0" }
          desc = { fg = "text" }
          separator = "  "
          separator_style = { fg = "surface2" }
        '';
      };
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
    ];

    # Ripgrep configuration file
    home-manager.users.yuki.home.file.".config/ripgrep/config" = mkIf cfg.search-tools {
      text = ''
        # Ripgrep configuration
        --smart-case
        --follow
        --hidden
        --glob=!.git/*
        --glob=!node_modules/*
        --glob=!.next/*
        --glob=!dist/*
        --glob=!build/*
        --glob=!target/*
        --glob=!.cache/*
        --glob=!*.lock
        --colors=line:style:bold
        --colors=path:fg:blue
        --colors=match:fg:red
        --colors=match:style:bold
      '';
    };
  };
}