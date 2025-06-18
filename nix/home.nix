{ config, pkgs, lib, username, homeDirectory, dotfilesDirectory, ... }:

let
  # Import unified theme configuration (SSOT)
  theme = import ./theme.nix { };
in

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
    
    # Package managers and runtimes
    nodejs_20    # Node.js LTS
    python312    # Python 3.12
    python312Packages.pip  # pip for Python
    python312Packages.virtualenv  # Virtual environments
    python312Packages.pipx  # Install Python applications in isolated environments
    
    # Package management tools
    yarn     # Alternative Node.js package manager
    pnpm     # Fast, disk space efficient package manager
    
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
      initExtra = lib.mkBefore ''
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
        
        # Claude Code shortcuts (non-interactive mode)
        claude-ask = "claude --print";
        claude-review = "claude --print 'このコードをレビューしてください:'";
        claude-fix = "claude --print 'このエラーの修正方法は？'";
        claude-optimize = "claude --print 'このコードを最適化してください:'";
        claude-doc = "claude --print 'このコードのドキュメントを生成してください:'";
        
        # Package manager shortcuts
        ni = "npm install";
        nu = "npm uninstall";
        nr = "npm run";
        ns = "npm start";
        nt = "npm test";
        nb = "npm run build";
        
        # Python shortcuts
        py = "python3";
        pip = "pip3";
        venv = "python3 -m venv";
        activate = "source ./venv/bin/activate";
        
        # Yarn/pnpm alternatives
        yi = "yarn install";
        ya = "yarn add";
        yr = "yarn run";
        pi = "pnpm install";
        pa = "pnpm add";
        pr = "pnpm run";
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

    # Atuin - enhanced shell history
    atuin = {
      enable = true;
      enableZshIntegration = true;
      enableBashIntegration = true;
      settings = {
        # Sync configuration (optional - can be disabled for privacy)
        sync_address = "https://api.atuin.sh";
        auto_sync = false;  # Disable automatic sync for privacy
        
        # History settings
        update_check = false;
        search_mode = "fuzzy";
        filter_mode = "global";
        filter_mode_shell = "session";
        inline_height = 15;
        show_preview = true;
        max_preview_height = 4;
        
        # Key bindings - use Ctrl+R for search
        keymap_mode = "auto";
        
        # Privacy settings
        secrets_filter = true;
        
        # Storage settings
        history_filter = [
          "^cd "
          "^ls "
          "^ll "
          "^la "
          "^pwd"
          "^exit"
          "^clear"
          "^history"
        ];
        
        # UI settings
        style = "compact";
        show_help = true;
        exit_mode = "return-original";
        
        # Statistics
        common_prefix = ["sudo"];
        common_subcommands = [
          "git"
          "cargo"
          "npm"
          "yarn"
          "docker"
          "kubectl"
          "nix"
          "home-manager"
          "darwin-rebuild"
        ];
      };
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

    # Node.js development environment
    # Note: npm is managed via nodejs package installation
    # Global npm packages should be installed via nix when possible

    # Python development environment  
    # Note: Python packages managed via nix expressions rather than pip when possible
  };

  # File management - Dotfiles deployment via home-manager
  # Migrated from scripts/install.sh DOTFILES_LIST for declarative configuration
  home.file = {
    # Phase 1: 基本設定（必須）
    ".zshrc".source = ../configs/zsh/zshrc;
    ".zprofile".source = ../configs/zsh/zprofile;
    ".config/starship.toml".source = ../configs/terminal/starship.toml;
    # Wezterm config with theme integration (SSOT)
    ".config/wezterm/wezterm.lua".text = ''
      local wezterm = require 'wezterm'
      local config = wezterm.config_builder()
      
      -- カラースキーム設定（自動切り替え）
      local function scheme_for_appearance(appearance)
        if appearance:find 'Dark' then
          return 'Catppuccin Mocha'
        else
          return 'Catppuccin Latte'
        end
      end
      config.color_scheme = scheme_for_appearance(wezterm.gui.get_appearance())
      
      -- フォント設定 (SSOT from theme.nix)
      config.font = wezterm.font_with_fallback {
        '${theme.fonts.primary}',
        'SF Mono',
        'Menlo',
        'Monaco',
      }
      config.font_size = ${toString theme.fonts.size.medium}.0
      config.line_height = 1.2
      config.freetype_load_target = 'HorizontalLcd'
      
      -- カラー設定 (SSOT from theme.nix)
      config.colors = {
        foreground = '${theme.colors.text}',
        background = '${theme.colors.base}',
        cursor_bg = '${theme.colors.blue}',
        cursor_fg = '${theme.colors.text}',
        cursor_border = '${theme.colors.blue}',
        selection_fg = '${theme.colors.text}',
        selection_bg = '${theme.colors.surface1}',
        scrollbar_thumb = '${theme.colors.surface0}',
        split = '${theme.colors.surface0}',
        
        ansi = {
          '${theme.colors.surface1}', -- black
          '${theme.colors.red}',      -- red
          '${theme.colors.green}',    -- green
          '${theme.colors.yellow}',   -- yellow
          '${theme.colors.blue}',     -- blue
          '${theme.colors.mauve}',    -- magenta
          '${theme.colors.teal}',     -- cyan
          '${theme.colors.subtext1}', -- white
        },
        brights = {
          '${theme.colors.surface2}', -- bright black
          '${theme.colors.red}',      -- bright red
          '${theme.colors.green}',    -- bright green
          '${theme.colors.yellow}',   -- bright yellow
          '${theme.colors.blue}',     -- bright blue
          '${theme.colors.mauve}',    -- bright magenta
          '${theme.colors.teal}',     -- bright cyan
          '${theme.colors.text}',     -- bright white
        },
      }
      
      -- ターミナル設定
      config.enable_tab_bar = false
      config.window_decorations = "RESIZE"
      config.window_background_opacity = 0.95
      config.macos_window_background_blur = 20
      
      -- その他の設定
      config.audible_bell = "Disabled"
      config.scrollback_lines = 10000
      config.enable_scroll_bar = false
      
      return config
    '';
    ".tmux.conf".source = ../configs/terminal/tmux.conf;
    
    # Phase 2: 開発ツール設定
    ".condarc".source = ../configs/development/.condarc;
    ".docker/config.json".source = ../configs/development/docker/config.json;
    ".docker/daemon.json".source = ../configs/development/docker/daemon.json;
    ".config/gh/config.yml".source = ../configs/cli/gh/config.yml;
    ".config/claude/mcp-servers.json".source = ../configs/apps/claude/mcp-servers.json;
    
    # Phase 3: エディター設定（任意）
    ".config/zed/settings.json".source = ../configs/editors/zed/settings.json;
    "Library/Application Support/Code/User/settings.json".source = ../configs/editors/vscode/settings.json;
    ".config/nvim".source = ../configs/editors/nvim;
    
    # Phase 4: ウィンドウマネージャー設定（macOS限定・任意）
    ".config/yabai/yabairc".source = ../configs/wm/yabai/yabairc;
    ".config/skhd/skhdrc".source = ../configs/wm/skhd/skhdrc;
    ".config/sketchybar/sketchybarrc".source = ../configs/wm/sketchybar/sketchybarrc;
    
    # Note: Sensitive files (.gitconfig, ssh/config, claude.json) are excluded for security
    # See .example files in respective directories for templates
  };

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
    
    # Package manager configurations
    NODE_OPTIONS = "--max-old-space-size=4096";
    NPM_CONFIG_PREFIX = "${homeDirectory}/.npm-global";
    PYTHON_VENV_PATH = "${homeDirectory}/.local/share/virtualenvs";
    
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
    # Note: System-level defaults managed via nix-darwin
  };
}