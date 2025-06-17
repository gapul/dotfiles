# マルチプラットフォーム対応アーキテクチャ設計書

## 概要

現在のmacOS特化のnix-darwin設定から、4つのプラットフォーム（macOS、Linux、WSL、Android）をサポートする包括的なdotfiles管理システムへの拡張設計。

## 対象プラットフォーム分析

### 1. macOS (aarch64-darwin / x86_64-darwin)
**現在の実装状況**: ✅ 完全対応済み
- **システム管理**: nix-darwin
- **ユーザー管理**: home-manager (統合)
- **パッケージ管理**: nixpkgs + Homebrew (GUI)
- **制約**: GUI アプリは主にHomebrew経由

### 2. Linux NixOS (aarch64-linux / x86_64-linux)
**実装必要度**: 🔴 高優先度
- **システム管理**: NixOS configuration
- **ユーザー管理**: home-manager (統合)
- **パッケージ管理**: nixpkgs (完全対応)
- **利点**: 最も柔軟なNix環境

### 3. Linux non-NixOS (Ubuntu/Debian/etc)
**実装必要度**: 🟡 中優先度
- **システム管理**: 従来の方法 (sudo/package manager)
- **ユーザー管理**: home-manager (standalone)
- **パッケージ管理**: nixpkgs (制約あり)
- **制約**: GUI問題、要 `targets.genericLinux.enable = true`

### 4. Windows WSL (Ubuntu/Debian)
**実装必要度**: 🟡 中優先度
- **システム管理**: WSL + Linux distribution
- **ユーザー管理**: home-manager (standalone)
- **パッケージ管理**: nixpkgs (x86_64-linux)
- **制約**: systemd制限、Windows統合

### 5. Android (nix-on-droid)
**実装必要度**: 🟢 低優先度 (実験的)
- **システム管理**: nix-on-droid
- **ユーザー管理**: 専用設定
- **パッケージ管理**: nixpkgs (aarch64-linux subset)
- **制約**: アルファ品質、重大な制約

## 新しいディレクトリ構造設計

```
dotfiles/
├── platforms/                    # プラットフォーム固有設定
│   ├── common/                   # 全プラットフォーム共通
│   │   ├── home-manager/         # 共通home-manager設定
│   │   │   ├── programs/         # プログラム設定
│   │   │   │   ├── terminal.nix  # ターミナル系ツール
│   │   │   │   ├── editors.nix   # エディター設定
│   │   │   │   ├── development.nix # 開発ツール
│   │   │   │   └── shell.nix     # シェル設定
│   │   │   ├── packages/         # パッケージ定義
│   │   │   │   ├── cli-tools.nix
│   │   │   │   ├── development.nix
│   │   │   │   └── utilities.nix
│   │   │   └── services/         # サービス設定
│   │   ├── theme.nix             # 統一テーマ設定
│   │   ├── fonts.nix             # フォント設定
│   │   └── aliases.nix           # 共通エイリアス
│   │
│   ├── darwin/                   # macOS (現在の設定)
│   │   ├── default.nix           # Darwin設定エントリーポイント
│   │   ├── system.nix            # macOS システム設定
│   │   ├── homebrew.nix          # Homebrew設定
│   │   ├── preferences.nix       # macOS 環境設定
│   │   └── home-manager.nix      # Darwin統合home-manager
│   │
│   ├── nixos/                    # Linux NixOS
│   │   ├── default.nix           # NixOS設定エントリーポイント
│   │   ├── hardware/             # ハードウェア設定
│   │   │   ├── desktop.nix
│   │   │   ├── laptop.nix
│   │   │   └── server.nix
│   │   ├── desktop/              # デスクトップ環境
│   │   │   ├── gnome.nix
│   │   │   ├── kde.nix
│   │   │   └── i3.nix
│   │   ├── services/             # システムサービス
│   │   └── home-manager.nix      # NixOS統合home-manager
│   │
│   ├── linux-standalone/         # non-NixOS Linux
│   │   ├── default.nix           # standalone home-manager
│   │   ├── generic-linux.nix     # GenericLinux対応
│   │   ├── distributions/        # ディストリ別対応
│   │   │   ├── ubuntu.nix
│   │   │   ├── debian.nix
│   │   │   ├── fedora.nix
│   │   │   └── arch.nix
│   │   └── gui-fixes.nix         # GUI問題修正
│   │
│   ├── wsl/                      # Windows WSL
│   │   ├── default.nix           # WSL設定
│   │   ├── wsl-integration.nix   # Windows統合
│   │   ├── ubuntu.nix            # Ubuntu WSL
│   │   ├── debian.nix            # Debian WSL
│   │   └── home-manager.nix      # WSL用home-manager
│   │
│   └── android/                  # Android (nix-on-droid)
│       ├── default.nix           # nix-on-droid設定
│       ├── termux-compat.nix     # Termux互換
│       ├── mobile-optimized.nix  # モバイル最適化
│       └── limited-packages.nix  # 制限されたパッケージセット
│
├── flakes/                       # プラットフォーム別flake
│   ├── darwin.nix                # macOS flake
│   ├── nixos.nix                 # NixOS flake  
│   ├── linux-standalone.nix      # standalone Linux flake
│   ├── wsl.nix                   # WSL flake
│   └── android.nix               # Android flake
│
├── lib/                          # 共通ライブラリ関数
│   ├── platform-detection.nix    # プラットフォーム検出
│   ├── package-compatibility.nix # パッケージ互換性チェック
│   ├── conditional-config.nix    # 条件付き設定
│   └── utils.nix                 # ユーティリティ関数
│
├── configs/                      # 既存設定ファイル (変更なし)
│   └── (既存構造を維持)
│
├── scripts/                      # 既存スクリプト + プラットフォーム対応
│   ├── detect-platform.sh       # プラットフォーム検出
│   ├── install-nix.sh            # Nix自動インストール
│   ├── setup-platform.sh        # プラットフォーム別セットアップ
│   └── (既存スクリプト)
│
└── flake.nix                     # メインflakeエントリーポイント

## プラットフォーム検出ロジック

### 1. 自動検出メカニズム

```bash
# scripts/detect-platform.sh の設計
detect_platform() {
    # Android (nix-on-droid)
    if [[ -n "$NIX_ON_DROID" ]] || [[ "$OSTYPE" == "linux-android"* ]]; then
        echo "android"
        return
    fi
    
    # WSL検出
    if [[ -f /proc/version ]] && grep -q "Microsoft\|WSL" /proc/version; then
        # WSLディストリビューション判定
        if [[ -f /etc/os-release ]]; then
            source /etc/os-release
            case "$ID" in
                ubuntu) echo "wsl-ubuntu" ;;
                debian) echo "wsl-debian" ;;
                *) echo "wsl-generic" ;;
            esac
        else
            echo "wsl-generic"
        fi
        return
    fi
    
    # Darwin (macOS)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if [[ "$(uname -m)" == "arm64" ]]; then
            echo "darwin-aarch64"
        else
            echo "darwin-x86_64"
        fi
        return
    fi
    
    # Linux判定
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # NixOS判定
        if [[ -f /etc/NIXOS ]]; then
            if [[ "$(uname -m)" == "aarch64" ]]; then
                echo "nixos-aarch64"
            else
                echo "nixos-x86_64"
            fi
        else
            # 非NixOS Linux (ディストリビューション判定)
            if [[ -f /etc/os-release ]]; then
                source /etc/os-release
                case "$ID" in
                    ubuntu) echo "linux-ubuntu" ;;
                    debian) echo "linux-debian" ;;
                    fedora) echo "linux-fedora" ;;
                    arch) echo "linux-arch" ;;
                    *) echo "linux-generic" ;;
                esac
            else
                echo "linux-generic"
            fi
        fi
        return
    fi
    
    # 不明なプラットフォーム
    echo "unknown"
}
```

### 2. Nixプラットフォーム対応表

| プラットフォーム | System Architecture | Nix管理方式 | 制約・特徴 |
|----------------|-------------------|-----------|----------|
| macOS Intel | `x86_64-darwin` | nix-darwin + home-manager | GUI app制限 |
| macOS Apple Silicon | `aarch64-darwin` | nix-darwin + home-manager | GUI app制限 |
| NixOS Intel | `x86_64-linux` | NixOS + home-manager | フル機能 |
| NixOS ARM | `aarch64-linux` | NixOS + home-manager | フル機能 |
| Ubuntu/Debian | `x86_64-linux` | home-manager standalone | GUI問題あり |
| WSL Ubuntu | `x86_64-linux` | home-manager standalone | Windows統合 |
| Android | `aarch64-linux` | nix-on-droid | アルファ品質 |

## 条件分岐設定システム

### 1. プラットフォーム別パッケージ選択

```nix
# lib/package-compatibility.nix
{ pkgs, stdenv, ... }:

let
  isLinux = stdenv.isLinux;
  isDarwin = stdenv.isDarwin;
  isNixOS = builtins.pathExists /etc/NIXOS;
  isAndroid = builtins.getEnv "NIX_ON_DROID" != "";
  
  # プラットフォーム別パッケージリスト
  commonPackages = with pkgs; [
    # 全プラットフォーム共通
    git
    neovim
    tmux
    starship
    zsh
    fzf
    ripgrep
  ];
  
  linuxOnlyPackages = with pkgs; lib.optionals isLinux [
    # Linux専用パッケージ
    systemd
    xclip
    wl-clipboard
  ];
  
  darwinOnlyPackages = with pkgs; lib.optionals isDarwin [
    # macOS専用パッケージ  
    mas
    reattach-to-user-namespace
  ];
  
  guiPackages = with pkgs; lib.optionals (!isAndroid) [
    # GUI アプリ (Android以外)
    firefox
    # Linux: 問題がある場合は除外
  ] ++ lib.optionals (isLinux && !isNixOS) [
    # 非NixOS Linux: GUI修正が必要
  ];
  
  androidLimitedPackages = with pkgs; lib.optionals isAndroid [
    # Android制限パッケージ
    termux-api  # Termux API bridge (if available)
  ];
  
in {
  # 最終パッケージリスト
  allPackages = commonPackages 
    ++ linuxOnlyPackages 
    ++ darwinOnlyPackages 
    ++ guiPackages
    ++ androidLimitedPackages;
    
  # プラットフォーム別設定
  platformConfig = {
    enableGenericLinux = isLinux && !isNixOS;
    enableSystemdUser = isLinux && !isAndroid;
    enableGUI = !isAndroid;
    enableDarwinPreferences = isDarwin;
  };
}
```

### 2. 条件付きプログラム設定

```nix
# platforms/common/home-manager/programs/conditional.nix
{ config, pkgs, lib, ... }:

let
  inherit (pkgs.stdenv) isDarwin isLinux;
  isNixOS = builtins.pathExists /etc/NIXOS;
  isAndroid = builtins.getEnv "NIX_ON_DROID" != "";
in
{
  programs = {
    # シェル設定 (全プラットフォーム)
    zsh = {
      enable = true;
      # プラットフォーム別エイリアス
      shellAliases = {
        # 共通エイリアス
        ll = "eza -l";
        la = "eza -la";
        
        # Darwin専用
        brew = lib.mkIf isDarwin "echo 'Use: darwin-rebuild switch'";
        
        # Linux専用  
        apt = lib.mkIf (isLinux && !isNixOS) "echo 'Use: home-manager switch'";
        
        # NixOS専用
        nixos-rebuild = lib.mkIf isNixOS "sudo nixos-rebuild switch";
        
        # Android専用
        termux-reload = lib.mkIf isAndroid "nix-on-droid switch";
      };
    };
    
    # Git設定 (プラットフォーム共通)
    git = {
      enable = true;
      extraConfig = {
        # Darwin: Keychain統合
        credential.helper = lib.mkIf isDarwin "osxkeychain";
        
        # Linux: 適切なエディター設定
        core.editor = lib.mkIf isLinux "nvim";
      };
    };
    
    # ターミナル設定
    alacritty = {
      enable = !isAndroid;  # Android以外で有効
      settings = {
        # プラットフォーム別フォント
        font.normal.family = 
          if isDarwin then "SF Mono" 
          else if isLinux then "DejaVu Sans Mono"
          else "monospace";
      };
    };
    
    # GUI設定 (Android以外)
    firefox = {
      enable = !isAndroid && !isDarwin;  # Linux (NixOS)のみ
    };
  };
  
  # プラットフォーム別ターゲット設定
  targets = {
    # 非NixOS Linux用設定
    genericLinux = lib.mkIf (isLinux && !isNixOS) {
      enable = true;
    };
  };
  
  # プラットフォーム別サービス
  services = lib.mkIf (isLinux && !isAndroid) {
    # Linux用systemdサービス
    syncthing.enable = true;
  };
}
```

## メインflake.nix設計

### 統合flake構造

```nix
# flake.nix (ルート)
{
  description = "マルチプラットフォーム対応 dotfiles with Nix";

  inputs = {
    # Core inputs
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    
    # Platform-specific managers
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Specialized inputs
    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/release-23.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Utilities
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nix-darwin, home-manager, nix-on-droid, flake-utils }:
    let
      # ユーザー情報
      username = "yuki";
      
      # システム別設定
      systems = {
        darwin = {
          x86_64 = "x86_64-darwin";
          aarch64 = "aarch64-darwin";
        };
        linux = {
          x86_64 = "x86_64-linux";
          aarch64 = "aarch64-linux";
        };
      };
      
      # 共通設定
      commonArgs = system: {
        inherit username;
        homeDirectory = if nixpkgs.lib.strings.hasSuffix "darwin" system 
                       then "/Users/${username}"
                       else "/home/${username}";
        dotfilesDirectory = if nixpkgs.lib.strings.hasSuffix "darwin" system
                           then "/Users/${username}/dotfiles"  
                           else "/home/${username}/dotfiles";
      };
      
    in
    {
      # macOS設定 (既存)
      darwinConfigurations = {
        # Apple Silicon Mac
        "aarch64" = nix-darwin.lib.darwinSystem {
          system = systems.darwin.aarch64;
          specialArgs = commonArgs systems.darwin.aarch64;
          modules = [
            ./platforms/darwin
            home-manager.darwinModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;  
                users.${username} = import ./platforms/darwin/home-manager.nix;
                extraSpecialArgs = commonArgs systems.darwin.aarch64;
              };
            }
          ];  
        };
        
        # Intel Mac
        "x86_64" = nix-darwin.lib.darwinSystem {
          system = systems.darwin.x86_64;
          specialArgs = commonArgs systems.darwin.x86_64;
          modules = [
            ./platforms/darwin
            home-manager.darwinModules.home-manager  
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users.${username} = import ./platforms/darwin/home-manager.nix;
                extraSpecialArgs = commonArgs systems.darwin.x86_64;
              };
            }
          ];
        };
      };
      
      # NixOS設定
      nixosConfigurations = {
        # x86_64 NixOS
        "nixos-desktop" = nixpkgs.lib.nixosSystem {
          system = systems.linux.x86_64;
          specialArgs = commonArgs systems.linux.x86_64;
          modules = [
            ./platforms/nixos
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users.${username} = import ./platforms/nixos/home-manager.nix;
                extraSpecialArgs = commonArgs systems.linux.x86_64;
              };
            }
          ];
        };
        
        # aarch64 NixOS (ARM server/SBC)
        "nixos-server" = nixpkgs.lib.nixosSystem {
          system = systems.linux.aarch64;
          specialArgs = commonArgs systems.linux.aarch64;
          modules = [
            ./platforms/nixos
            ./platforms/nixos/hardware/server.nix
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users.${username} = import ./platforms/nixos/home-manager.nix;
                extraSpecialArgs = commonArgs systems.linux.aarch64;
              };
            }
          ];
        };
      };
      
      # Standalone Home Manager (非NixOS Linux, WSL)
      homeConfigurations = {
        # Linux Standalone (Ubuntu/Debian/etc)
        "${username}@linux" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${systems.linux.x86_64};
          extraSpecialArgs = commonArgs systems.linux.x86_64;
          modules = [ ./platforms/linux-standalone ];
        };
        
        # WSL Ubuntu
        "${username}@wsl-ubuntu" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${systems.linux.x86_64};
          extraSpecialArgs = (commonArgs systems.linux.x86_64) // { isWSL = true; };
          modules = [ 
            ./platforms/wsl
            ./platforms/wsl/ubuntu.nix
          ];
        };
        
        # WSL Debian  
        "${username}@wsl-debian" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${systems.linux.x86_64};
          extraSpecialArgs = (commonArgs systems.linux.x86_64) // { isWSL = true; };
          modules = [
            ./platforms/wsl
            ./platforms/wsl/debian.nix
          ];
        };
      };
      
      # Android (nix-on-droid)
      nixOnDroidConfigurations = {
        "android-device" = nix-on-droid.lib.nixOnDroidConfiguration {
          system = systems.linux.aarch64;
          specialArgs = (commonArgs systems.linux.aarch64) // { 
            isAndroid = true;
            homeDirectory = "/data/data/com.termux.nix/files/home";
          };
          modules = [ ./platforms/android ];
        };
      };
      
      # 開発環境
      devShells = flake-utils.lib.eachDefaultSystem (system: {
        default = nixpkgs.legacyPackages.${system}.mkShell {
          buildInputs = with nixpkgs.legacyPackages.${system}; [
            git
            nix
            home-manager
            (if nixpkgs.lib.strings.hasSuffix "darwin" system 
             then nix-darwin.packages.${system}.default
             else nixpkgs.legacyPackages.${system}.hello)
          ];
          shellHook = ''
            echo "🚀 Multi-platform dotfiles development environment"
            echo "Platform: ${system}"
            echo "Available commands:"
            echo "  - home-manager"
            ${if nixpkgs.lib.strings.hasSuffix "darwin" system 
              then "echo '  - darwin-rebuild'"
              else ""}
          '';
        };
      });
    };
}
```

## 共通設定vs個別設定の分離戦略

### 1. 設定分離の原則

#### 共通設定（platforms/common/）
- **CLI ツール設定**: 全プラットフォームで同一動作が期待されるもの
- **開発環境**: 言語ランタイム、エディター、Git設定
- **テーマ・外観**: 色設定、フォント（プラットフォーム別フォールバック付き）
- **シェル設定**: 基本的なzsh設定、エイリアス、関数

#### プラットフォーム固有設定
- **システム統合**: OS固有のAPIやサービス連携
- **GUI アプリケーション**: プラットフォーム固有のアプリ
- **ハードウェア対応**: ディスプレイ、入力デバイス設定
- **パッケージマネージャー統合**: Homebrew、APT等

### 2. 設定継承システム

```nix
# platforms/common/base.nix - 基本設定
{ config, pkgs, lib, ... }:
{
  # 全プラットフォーム共通の基本設定
  imports = [
    ./home-manager/programs/terminal.nix
    ./home-manager/programs/editors.nix
    ./home-manager/programs/development.nix
    ./home-manager/programs/shell.nix
    ./theme.nix
    ./fonts.nix
    ./aliases.nix
  ];
  
  # 基本パッケージ（全プラットフォーム対応）
  home.packages = with pkgs; [
    # Core CLI tools (全プラットフォーム利用可能)
    git
    neovim
    tmux
    starship
    zsh
    fzf
    ripgrep
    fd
    bat
    eza
    zoxide
    jq
    curl
    wget
  ];
  
  # 基本設定
  home.stateVersion = "24.05";
  
  # XDG設定（Linux/Unix共通）
  xdg.enable = true;
}
```

```nix
# platforms/darwin/default.nix - macOS特化設定
{ config, pkgs, lib, username, homeDirectory, dotfilesDirectory, ... }:
{
  # 共通設定をインポート
  imports = [
    ../common/base.nix
    ./homebrew.nix
    ./system.nix
    ./preferences.nix
  ];
  
  # macOS固有パッケージ追加
  home.packages = with pkgs; [
    # Darwin-specific packages
    mas
    reattach-to-user-namespace
  ];
  
  # macOS固有プログラム設定
  programs = {
    # macOS Keychain統合
    git.extraConfig.credential.helper = "osxkeychain";
    
    # macOS特有のエイリアス
    zsh.shellAliases = {
      # Darwin rebuild shortcut
      nrs = "darwin-rebuild switch --flake ${dotfilesDirectory}/nix";
      
      # macOS specific commands
      flushdns = "sudo dscacheutil -flushcache";
      airport = "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport";
    };
  };
  
  # macOS固有のファイル管理
  home.file = {
    # macOS specific config files
    "Library/Application Support/Code/User/settings.json".source = 
      "${dotfilesDirectory}/configs/editors/vscode/settings.json";
      
    # Yabai (macOS window manager)
    ".config/yabai/yabairc".source = 
      "${dotfilesDirectory}/configs/wm/yabai/yabairc";
  };
}
```

```nix
# platforms/nixos/default.nix - NixOS特化設定
{ config, pkgs, lib, username, homeDirectory, dotfilesDirectory, ... }:
{
  # 共通設定をインポート
  imports = [
    ../common/base.nix
    ./hardware-configuration.nix
    ./desktop-environment.nix
    ./services.nix
  ];
  
  # NixOS固有パッケージ
  home.packages = with pkgs; [
    # Linux-specific GUI apps (NixOS optimized)
    firefox
    thunderbird
    xclip
    wl-clipboard
    
    # System utilities
    systemd
    udev
  ];
  
  # NixOS固有プログラム設定
  programs = {
    # Linux Git設定
    git.extraConfig.core.editor = "nvim";
    
    # NixOS特有のエイリアス
    zsh.shellAliases = {
      # NixOS rebuild shortcut
      nixos-rebuild = "sudo nixos-rebuild switch";
      hms = "home-manager switch --flake ${dotfilesDirectory}/nix";
      
      # System maintenance
      nix-clean = "sudo nix-collect-garbage -d";
      nixos-upgrade = "sudo nixos-rebuild switch --upgrade";
    };
  };
  
  # Linux GUI対応
  targets.genericLinux.enable = false;  # NixOSでは不要
  
  # systemd user services
  services = {
    syncthing.enable = true;
    redshift.enable = true;
  };
}
```

```nix
# platforms/linux-standalone/default.nix - 非NixOS Linux
{ config, pkgs, lib, username, homeDirectory, dotfilesDirectory, ... }:
{
  # 共通設定をインポート
  imports = [
    ../common/base.nix
    ./generic-linux.nix
    ./gui-fixes.nix
  ];
  
  # Linux standalone固有設定
  home.packages = with pkgs; [
    # 基本的なLinuxパッケージのみ
    # GUI関連は制限あり
  ];
  
  # 非NixOS Linux特有の設定
  targets.genericLinux.enable = true;  # 重要: GUI修正
  
  programs = {
    # Linux standalone用エイリアス
    zsh.shellAliases = {
      hms = "home-manager switch --flake ${dotfilesDirectory}/nix";
      
      # System integration helpers
      check-nixgl = "echo $NIXGL_PREFIX";
      with-gl = "nixgl";  # NixGL wrapper
    };
  };
  
  # 制限されたサービス設定
  services = {
    # GUI関連サービスは慎重に
  };
}
```

### 3. テーマ・外観の統一管理

```nix
# platforms/common/theme.nix
{ pkgs, lib, ... }:
let
  # Catppuccin color scheme (全プラットフォーム統一)
  colors = {
    base = "#1e1e2e";
    surface = "#313244";
    text = "#cdd6f4";
    accent = "#89b4fa";
    warning = "#f9e2af";
    error = "#f38ba8";
  };
  
  # プラットフォーム別フォント設定
  fonts = {
    monospace = {
      darwin = "SF Mono";
      linux = "JetBrains Mono";
      fallback = "monospace";
    };
    
    ui = {
      darwin = "SF Pro Text";
      linux = "Inter";
      fallback = "sans-serif";
    };
  };
in
{
  # 統一テーマをエクスポート
  home.sessionVariables = {
    THEME_BASE = colors.base;
    THEME_ACCENT = colors.accent;
  };
  
  programs = {
    # Neovim: 統一テーマ
    neovim.extraConfig = ''
      colorscheme catppuccin-mocha
    '';
    
    # Starship: 統一テーマ
    starship.settings = {
      palette = "catppuccin_mocha";
    };
    
    # Bat: 統一テーマ
    bat.config.theme = "Catppuccin-mocha";
    
    # Alacritty: プラットフォーム対応テーマ
    alacritty.settings = {
      colors = {
        primary = {
          background = colors.base;
          foreground = colors.text;
        };
      };
      
      font.normal.family = 
        if pkgs.stdenv.isDarwin then fonts.monospace.darwin
        else if pkgs.stdenv.isLinux then fonts.monospace.linux
        else fonts.monospace.fallback;
    };
  };
}
```

### 4. 条件分岐設定パターン

```nix
# platforms/common/home-manager/programs/conditional.nix
{ config, pkgs, lib, ... }:
let
  inherit (pkgs.stdenv) isDarwin isLinux;
  isNixOS = builtins.pathExists /etc/NIXOS;
  isAndroid = builtins.getEnv "NIX_ON_DROID" != "";
  isWSL = builtins.getEnv "WSL_DISTRO_NAME" != "";
in
{
  # 条件付きプログラム有効化
  programs = {
    # デスクトップ環境限定
    firefox.enable = isLinux && isNixOS && !isAndroid;
    
    # ターミナル環境（モバイル以外）
    alacritty.enable = !isAndroid;
    wezterm.enable = !isAndroid;
    
    # 開発環境（全プラットフォーム）
    git.enable = true;
    neovim.enable = true;
    
    # プラットフォーム別Git設定
    git.extraConfig = lib.mkMerge [
      # 共通設定
      {
        init.defaultBranch = "main";
        push.default = "simple";
      }
      
      # Darwin固有
      (lib.mkIf isDarwin {
        credential.helper = "osxkeychain";
      })
      
      # Linux固有
      (lib.mkIf isLinux {
        core.editor = "nvim";
      })
      
      # WSL固有
      (lib.mkIf isWSL {
        core.autocrlf = "input";
      })
    ];
  };
  
  # 条件付きサービス
  services = lib.mkMerge [
    # Linux用サービス（Android除く）
    (lib.mkIf (isLinux && !isAndroid) {
      syncthing.enable = true;
    })
    
    # デスクトップ用サービス（GUI環境）
    (lib.mkIf (isLinux && isNixOS && !isAndroid) {
      redshift.enable = true;
    })
  ];
  
  # プラットフォーム別ターゲット設定
  targets = {
    # 非NixOS Linux用
    genericLinux.enable = isLinux && !isNixOS;
  };
}
```

### 5. パッケージ互換性管理

```nix
# lib/package-selection.nix
{ pkgs, lib, stdenv, ... }:
let
  inherit (stdenv) isDarwin isLinux;
  isNixOS = builtins.pathExists /etc/NIXOS;
  isAndroid = builtins.getEnv "NIX_ON_DROID" != "";
  
  # カテゴリ別パッケージ定義
  categories = {
    # Tier 1: 全プラットフォーム対応保証
    essential = with pkgs; [
      git
      neovim
      tmux
      starship
      zsh
      fzf
      ripgrep
      fd
      bat
      eza
      jq
      curl
      wget
    ];
    
    # Tier 2: プラットフォーム制限あり
    development = with pkgs; [
      nodejs_20
      python312
      go
      rustc
      cargo
    ] ++ lib.optionals (!isAndroid) [
      docker
      docker-compose
    ];
    
    # Tier 3: GUI関連（最も制限が多い）
    gui = with pkgs; lib.optionals (!isAndroid) [
      # Linux NixOSのみ確実
    ] ++ lib.optionals (isLinux && isNixOS) [
      firefox
      thunderbird
    ] ++ lib.optionals isDarwin [
      # macOSはHomebrew経由推奨
    ];
    
    # Tier 4: プラットフォーム固有
    platformSpecific = with pkgs; lib.optionals isDarwin [
      mas
      reattach-to-user-namespace
    ] ++ lib.optionals isLinux [
      xclip
      wl-clipboard
    ] ++ lib.optionals (isLinux && !isAndroid) [
      systemd
    ];
  };
  
in {
  # 最終パッケージリスト生成
  selectedPackages = 
    categories.essential ++
    categories.development ++
    categories.gui ++
    categories.platformSpecific;
    
  # プラットフォーム能力情報
  capabilities = {
    hasGUI = !isAndroid;
    hasSystemd = isLinux && !isAndroid;
    hasHomebrew = isDarwin;
    hasAPT = isLinux && !isNixOS;
    canUseDocker = !isAndroid;
  };
}
```

## 段階的移行計画

### Phase 1: 基盤準備（2週間）
**目標**: 現在のmacOS設定を維持しながら、マルチプラットフォーム対応基盤を構築

#### 1.1 ディレクトリ構造の作成
```bash
# 新しいディレクトリ構造を作成（既存設定と並列）
mkdir -p platforms/{common,darwin,nixos,linux-standalone,wsl,android}
mkdir -p platforms/common/home-manager/{programs,packages,services}
mkdir -p lib
mkdir -p flakes

# 既存設定はそのまま維持
# configs/ - 変更なし
# nix/    - 段階的に移行
```

#### 1.2 共通基盤モジュールの作成
1. **プラットフォーム検出ライブラリ**
   - `lib/platform-detection.nix` - Nixレベルでの検出
   - `scripts/detect-platform.sh` - シェルレベルでの検出

2. **共通設定モジュール**
   - `platforms/common/base.nix` - 基本設定
   - `platforms/common/theme.nix` - 統一テーマ
   - `platforms/common/packages.nix` - 共通パッケージ

3. **プラットフォーム互換性チェック**
   - `lib/package-compatibility.nix` - パッケージ選択ロジック

#### 1.3 現在のDarwin設定のリファクタリング
```bash
# 既存のnix/設定を新構造に移行
mv nix/darwin.nix platforms/darwin/system.nix
mv nix/home.nix platforms/darwin/home-manager.nix

# 新しいflake.nixの段階的導入
cp nix/flake.nix flake-multiplatform.nix  # 実験用
```

### Phase 2: Linux NixOS対応（2週間）
**目標**: NixOS用の設定を追加し、デスクトップLinux環境をサポート

#### 2.1 NixOS設定モジュールの作成
1. **基本NixOS設定**
   - `platforms/nixos/default.nix` - システム設定
   - `platforms/nixos/hardware/` - ハードウェア別設定
   - `platforms/nixos/desktop/` - デスクトップ環境設定

2. **サービス設定**
   - `platforms/nixos/services.nix` - systemdサービス
   - GUI環境設定（GNOME/KDE/i3対応）

#### 2.2 テスト環境の構築
```bash
# VirtualBox/UTM でNixOS VM作成
# または既存のLinux環境でテスト
nix build .#nixosConfigurations.nixos-desktop
```

#### 2.3 パッケージ互換性の検証
- Linux NixOS でのGUIアプリケーション動作確認
- systemd統合の検証
- 共通テーマの適用確認

### Phase 3: 非NixOS Linux対応（1週間）
**目標**: Ubuntu/Debian等でのstandalone home-manager対応

#### 3.1 Standalone設定の作成
1. **Linux standalone設定**
   - `platforms/linux-standalone/default.nix`
   - `platforms/linux-standalone/distributions/` - ディストリ別対応

2. **GUI問題の対策**
   - `targets.genericLinux.enable = true`
   - NixGL統合の検討

#### 3.2 テスト環境での検証
```bash
# Docker container でUbuntu/Debian環境作成
# home-manager standalone でのテスト
home-manager switch --flake .#username@linux
```

### Phase 4: WSL対応（1週間）
**目標**: Windows WSL環境でのNix/home-manager動作

#### 4.1 WSL固有設定の作成
1. **WSL統合設定**
   - `platforms/wsl/default.nix` - WSL固有設定
   - Windows PATH統合
   - ファイルシステム連携

2. **ディストリビューション別対応**
   - `platforms/wsl/ubuntu.nix`
   - `platforms/wsl/debian.nix`

#### 4.2 Windows統合機能
- Windows Terminal連携
- WSL1/WSL2両対応
- Windows側ツールとの統合

### Phase 5: Android対応（実験的・1週間）
**目標**: nix-on-droid環境での基本動作確認

#### 5.1 Android制限環境対応
1. **制限対応設定**
   - `platforms/android/default.nix` - 基本設定
   - `platforms/android/limited-packages.nix` - 制限パッケージ

2. **モバイル最適化**
   - GUI無効化
   - リソース消費の最適化
   - Termux API統合

#### 5.2 実験的テスト
```bash
# F-Droid からnix-on-droidインストール
# 基本動作確認のみ（本格運用は非推奨）
```

### Phase 6: 統合とテスト（1週間）
**目標**: 全プラットフォームでの動作確認と最適化

#### 6.1 統合flake.nixの完成
1. **メインflakeの切り替え**
   ```bash
   mv flake.nix flake-legacy.nix
   mv flake-multiplatform.nix flake.nix
   ```

2. **設定の最終調整**
   - 各プラットフォームでの動作確認
   - パフォーマンス最適化
   - 依存関係の整理

#### 6.2 ドキュメント作成
1. **プラットフォーム別セットアップガイド**
   - `docs/setup/MACOS.md`
   - `docs/setup/NIXOS.md`
   - `docs/setup/LINUX.md`
   - `docs/setup/WSL.md`
   - `docs/setup/ANDROID.md`

2. **移行ガイド**
   - 既存環境からの移行手順
   - トラブルシューティング

### 移行リスク管理

#### リスクアセスメント
| リスク | 影響度 | 対策 |
|--------|--------|------|
| 既存macOS環境の破損 | 高 | 段階的移行、バックアップ |
| GUI問題（非NixOS） | 中 | GenericLinux + NixGL |
| Android環境の不安定性 | 低 | 実験的位置付け |
| 設定複雑化 | 中 | モジュール化、文書化 |

#### 緊急時対応
```bash
# 問題発生時の即座ロールバック
git checkout main                    # 既存設定に戻る
darwin-rebuild switch --flake ./nix # 既存flakeで復旧
```

#### バックアップ戦略
1. **現在の動作環境の完全バックアップ**
   ```bash
   cp -r nix/ nix-backup-$(date +%Y%m%d)/
   git tag v-current-stable
   ```

2. **段階別チェックポイント**
   - 各Phase完了時点でタグ作成
   - 動作確認済み設定のコミット

### 成功指標

#### Phase完了基準
- **Phase 1**: 新構造で既存macOS環境が正常動作
- **Phase 2**: NixOS VM/実機で開発環境が動作
- **Phase 3**: Ubuntu/Debian で home-manager が動作
- **Phase 4**: WSL環境で基本開発環境が動作
- **Phase 5**: Android で基本CLIツールが動作（実験的）
- **Phase 6**: 全プラットフォームでの統合テスト成功

#### 品質指標
- CI/CDでの全flake評価成功
- 各プラットフォームでのキー機能動作確認
- パフォーマンス劣化無し
- 設定の保守性向上

## ベストプラクティス実装

### 1. 保守性の確保

#### モジュラー設計
```nix
# 良い例: 機能別モジュール分離
imports = [
  ./programs/git.nix       # Git設定のみ
  ./programs/neovim.nix    # Neovim設定のみ
  ./programs/terminal.nix  # ターミナル設定のみ
];

# 悪い例: 巨大な単一ファイル
# home.nix に全設定を記述
```

#### 条件分岐の集約
```nix
# 良い例: 条件をまとめて判定
let
  platform = {
    isDarwin = stdenv.isDarwin;
    isNixOS = builtins.pathExists /etc/NIXOS;
    isAndroid = builtins.getEnv "NIX_ON_DROID" != "";
  };
in
# 設定で platform.isDarwin を使用

# 悪い例: 各所で個別判定
programs.git.enable = stdenv.isDarwin || stdenv.isLinux;
services.syncthing.enable = !stdenv.isDarwin && !isAndroid;
```

### 2. 拡張性の設計

#### 新プラットフォーム追加手順
1. `platforms/新プラットフォーム/` ディレクトリ作成
2. `default.nix` で共通設定をインポート
3. プラットフォーム固有設定を追加
4. メイン `flake.nix` にConfiguration追加
5. CI/CDにテスト追加

#### プラグイン式モジュール
```nix
# platforms/common/plugins/ - オプション機能
plugins = {
  ai-tools.enable = true;      # AI開発ツール
  gaming.enable = false;       # ゲーム環境
  streaming.enable = false;    # 配信環境
  security.enable = true;      # セキュリティ強化
};
```

### 3. パフォーマンス最適化

#### ビルド時間短縮
- 共通依存関係の最適化
- プラットフォーム別キャッシュ活用
- 不要パッケージの除外

#### メモリ使用量管理
- Android: 軽量パッケージセット
- WSL: リソース制限への配慮
- Desktop: フル機能セット

### 4. セキュリティ考慮

#### 機密情報の分離
```nix
# 良い例: 環境別設定分離
imports = [
  ./secrets/personal.nix     # 個人情報
  ./secrets/work.nix         # 業務情報  
];

# 悪い例: ハードコード
programs.git.userEmail = "personal@example.com";
```

#### プラットフォーム別セキュリティ
- Android: 制限環境での動作
- WSL: Windows統合での情報漏洩防止
- Linux: sudo権限の適切な管理