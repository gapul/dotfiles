{ lib, pkgs, platform ? "unknown" }:

let
  isDarwin = platform == "darwin";
  isLinux = platform == "linux" || platform == "nixos";
  isWSL = platform == "wsl";
  isAndroid = platform == "android";
in
{
  # Tier 1: システム基盤 (Nix管理 - 最高優先度)
  systemCore = {
    # 基本システムツール
    coreutils = with pkgs; [
      coreutils     # ls, cp, mv, etc.
      findutils     # find, xargs
      gnused        # sed
      gnugrep       # grep
      gawk          # awk
      gnutar        # tar
      gzip          # gzip
      unzip         # unzip
    ];

    # ネットワークツール
    network = with pkgs; [
      curl          # HTTP client
      wget          # File downloader
      openssh       # SSH client/server
      rsync         # File synchronization
    ];

    # 開発基盤
    development = with pkgs; [
      git           # Version control
      just          # Task runner
      direnv        # Environment management
      nix-direnv    # Nix + direnv integration
    ];

    # モダンCLI置換 (頻繁更新許可)
    modernCli = with pkgs; [
      eza           # ls replacement
      bat           # cat replacement
      fd            # find replacement
      ripgrep       # grep replacement
      fzf           # fuzzy finder
      zoxide        # cd replacement
      du-dust       # du replacement
      procs         # ps replacement
    ];

    # システム監視
    monitoring = with pkgs; [
      htop          # Process viewer
      btop          # Modern htop
      bandwhich     # Network usage
      hyperfine     # Benchmarking
    ];
  };

  # Tier 2: GUIアプリケーション (プラットフォーム固有)
  guiApplications = {
    # macOS専用 (Homebrew Cask)
    macos = lib.optionals isDarwin [
      # GUI apps - Homebrewに委任
      # "wezterm" "aerospace" "claude" "raycast"
    ];

    # Linux GUI (Nix管理可能)
    linux = lib.optionals isLinux (with pkgs; [
      firefox       # Web browser
      alacritty     # Terminal emulator
      # その他のLinux GUIアプリ
    ]);

    # プラットフォーム固有ツール
    platformSpecific = lib.optionals isDarwin (with pkgs; [
      # macOS専用でNixで管理可能なもの
      m-cli         # macOS CLI tools
    ]) ++ lib.optionals isLinux (with pkgs; [
      # Linux専用ツール
      xclip         # Clipboard
      xdg-utils     # XDG utilities
    ]);
  };

  # Tier 3: 言語ランタイム (Nix + プロジェクト環境)
  languageRuntimes = {
    # 基本ランタイム（システムレベル）
    stable = with pkgs; [
      # 固定バージョン推奨
      nodejs_20     # Node.js LTS
      python311     # Python 3.11
      go_1_21       # Go stable
      rustc         # Rust latest stable
    ];

    # 開発支援ツール
    toolchains = with pkgs; [
      # Node.js エコシステム
      nodePackages.pnpm     # Fast package manager
      nodePackages.yarn     # Alternative package manager
      
      # Python エコシステム
      python311Packages.pip # Package installer
      python311Packages.virtualenv # Virtual environments
      
      # Rust エコシステム
      cargo         # Rust package manager
      rustfmt       # Rust formatter
      
      # Go エコシステム
      # 基本的にはgo moduleで管理
    ];

    # 追加言語 (必要に応じて)
    additional = with pkgs; [
      # PHP (必要な場合のみ)
      # php82
      # composer
      
      # Ruby (必要な場合のみ)
      # ruby_3_2
      # rubygems
      
      # Java (必要な場合のみ)
      # openjdk17
      # maven
    ];
  };

  # Tier 4: 開発ツール・エディタ拡張
  developmentTools = {
    # LSP・フォーマッタ（Nix管理）
    lspServers = with pkgs; [
      # Nix
      nil                                    # Nix LSP
      nixpkgs-fmt                           # Nix formatter
      
      # Web development
      nodePackages.typescript-language-server # TypeScript LSP
      nodePackages.vscode-langservers-extracted # HTML/CSS/JSON LSP
      nodePackages.prettier                 # Multi-language formatter
      
      # Python
      python311Packages.python-lsp-server   # Python LSP
      python311Packages.black               # Python formatter
      
      # Go
      gopls                                 # Go LSP
      gofumpt                              # Go formatter
      
      # Rust
      rust-analyzer                         # Rust LSP
      
      # Lua (for Neovim config)
      lua-language-server                   # Lua LSP
      stylua                               # Lua formatter
      
      # Shell
      shellcheck                           # Shell linter
      shfmt                               # Shell formatter
    ];

    # 開発支援ツール
    utilities = with pkgs; [
      # Version control
      gh            # GitHub CLI
      git-lfs       # Git Large File Storage
      
      # Container tools
      docker        # Container runtime
      docker-compose # Multi-container apps
      
      # Infrastructure
      terraform     # Infrastructure as Code
      kubectl       # Kubernetes CLI
      
      # Documentation
      mdbook        # Markdown book generator
      
      # Performance analysis
      flamegraph    # Performance profiling
    ];

    # エディタ固有（各エディタの管理に委任）
    editorSpecific = {
      # Neovim: lazy.nvim + mason.nvim
      # VSCode: extensions.json
      # Zed: settings.json
      # これらは各エディタの設定ファイルで管理
    };
  };

  # バージョン固定戦略
  pinnedVersions = {
    # 破壊的変更リスクの高いツール
    critical = {
      nodejs = "20.10.0";      # LTS版固定
      python = "3.11.7";       # 安定版固定
      terraform = "1.6.6";     # 設定互換性重視
      kubernetes = "1.28.4";    # クラスタ互換性重視
    };

    # 頻繁更新許可
    rolling = [
      "ripgrep" "fd" "bat" "eza" "fzf"    # CLI tools
      "git" "just" "direnv"               # 開発基盤
    ];
  };

  # パッケージセット組み立て
  packageSets = {
    # 最小構成（基本システムのみ）
    minimal = systemCore.coreutils ++ systemCore.network ++ systemCore.development;
    
    # 標準構成（一般的な開発環境）
    standard = self.minimal ++ systemCore.modernCli ++ systemCore.monitoring 
               ++ languageRuntimes.stable ++ developmentTools.lspServers;
    
    # 完全構成（全機能）
    full = self.standard ++ guiApplications.platformSpecific 
           ++ languageRuntimes.toolchains ++ developmentTools.utilities;
  };

  # プラットフォーム別推奨構成
  platformRecommended = {
    darwin = self.packageSets.standard ++ guiApplications.macos;
    linux = self.packageSets.standard ++ guiApplications.linux;
    nixos = self.packageSets.full;
    wsl = self.packageSets.standard;
    android = systemCore.coreutils ++ systemCore.development ++ systemCore.modernCli;
  };
}