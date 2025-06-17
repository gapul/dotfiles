# プラットフォーム検出実装例

このドキュメントでは、マルチプラットフォーム対応dotfilesシステムのプラットフォーム検出実装例を示します。

## シェルスクリプト実装例

```bash
#!/usr/bin/env bash
# scripts/detect-platform.sh
# プラットフォーム自動検出スクリプト

set -euo pipefail

# プラットフォーム検出関数
detect_platform() {
    local platform=""
    local arch=""
    local distro=""
    
    # アーキテクチャ検出
    case "$(uname -m)" in
        x86_64|amd64) arch="x86_64" ;;
        aarch64|arm64) arch="aarch64" ;;
        i686|i386) arch="i686" ;;
        *) arch="unknown" ;;
    esac
    
    # Android (nix-on-droid) 検出
    if [[ -n "${NIX_ON_DROID:-}" ]] || [[ "${OSTYPE}" == "linux-android"* ]]; then
        echo "android-${arch}"
        return 0
    fi
    
    # WSL検出
    if [[ -f /proc/version ]] && grep -qi "microsoft\|wsl" /proc/version; then
        if [[ -f /etc/os-release ]]; then
            source /etc/os-release
            case "${ID:-}" in
                ubuntu) distro="ubuntu" ;;
                debian) distro="debian" ;;
                fedora) distro="fedora" ;;
                arch) distro="arch" ;;
                *) distro="generic" ;;
            esac
        else
            distro="generic"
        fi
        echo "wsl-${distro}-${arch}"
        return 0
    fi
    
    # Darwin (macOS) 検出
    if [[ "${OSTYPE}" == "darwin"* ]]; then
        echo "darwin-${arch}"
        return 0
    fi
    
    # Linux検出
    if [[ "${OSTYPE}" == "linux-gnu"* ]] || [[ "$(uname -s)" == "Linux" ]]; then
        # NixOS判定
        if [[ -f /etc/NIXOS ]]; then
            echo "nixos-${arch}"
            return 0
        fi
        
        # 非NixOS Linux
        if [[ -f /etc/os-release ]]; then
            source /etc/os-release
            case "${ID:-}" in
                ubuntu) distro="ubuntu" ;;
                debian) distro="debian" ;;
                fedora) distro="fedora" ;;
                arch) distro="arch" ;;
                centos|rhel) distro="rhel" ;;
                opensuse*) distro="opensuse" ;;
                alpine) distro="alpine" ;;
                *) distro="generic" ;;
            esac
        else
            distro="generic"
        fi
        echo "linux-${distro}-${arch}"
        return 0
    fi
    
    # その他のUnix系
    case "${OSTYPE}" in
        freebsd*) echo "freebsd-${arch}" ;;
        openbsd*) echo "openbsd-${arch}" ;;
        netbsd*) echo "netbsd-${arch}" ;;
        solaris*) echo "solaris-${arch}" ;;
        *) echo "unknown-${arch}" ;;
    esac
}

# Nix system architecture 取得
get_nix_system() {
    local platform_info
    platform_info=$(detect_platform)
    
    case "${platform_info}" in
        # Darwin
        darwin-x86_64) echo "x86_64-darwin" ;;
        darwin-aarch64) echo "aarch64-darwin" ;;
        
        # Linux (NixOS)
        nixos-x86_64) echo "x86_64-linux" ;;
        nixos-aarch64) echo "aarch64-linux" ;;
        nixos-i686) echo "i686-linux" ;;
        
        # Linux (Non-NixOS)
        linux-*-x86_64) echo "x86_64-linux" ;;
        linux-*-aarch64) echo "aarch64-linux" ;;
        linux-*-i686) echo "i686-linux" ;;
        
        # WSL
        wsl-*-x86_64) echo "x86_64-linux" ;;
        wsl-*-aarch64) echo "aarch64-linux" ;;
        
        # Android
        android-aarch64) echo "aarch64-linux" ;;
        
        # その他
        *) echo "unsupported" ;;
    esac
}

# Nix flake configuration 取得
get_nix_config() {
    local platform_info
    platform_info=$(detect_platform)
    
    case "${platform_info}" in
        # Darwin
        darwin-*) echo "darwinConfigurations.default" ;;
        
        # NixOS
        nixos-*) echo "nixosConfigurations.default" ;;
        
        # Standalone Home Manager
        linux-*-*|wsl-*-*) echo "homeConfigurations.\${USER}@linux" ;;
        
        # Android
        android-*) echo "nixOnDroidConfigurations.default" ;;
        
        *) echo "unsupported" ;;
    esac
}

# 推奨されるパッケージマネージャー取得
get_package_manager() {
    local platform_info
    platform_info=$(detect_platform)
    
    case "${platform_info}" in
        darwin-*) echo "nix-darwin + homebrew" ;;
        nixos-*) echo "nixos + nix" ;;
        linux-ubuntu-*|wsl-ubuntu-*) echo "home-manager + apt" ;;
        linux-debian-*|wsl-debian-*) echo "home-manager + apt" ;;
        linux-fedora-*) echo "home-manager + dnf" ;;
        linux-arch-*) echo "home-manager + pacman" ;;
        android-*) echo "nix-on-droid" ;;
        *) echo "unknown" ;;
    esac
}

# 機能サポート確認
check_capabilities() {
    local platform_info
    platform_info=$(detect_platform)
    
    cat << EOF
Platform: ${platform_info}
Nix System: $(get_nix_system)
Package Manager: $(get_package_manager)

Capabilities:
$(case "${platform_info}" in
    darwin-*)
        echo "  ✅ GUI Applications (via Homebrew)"
        echo "  ✅ System Preferences"
        echo "  ✅ Nix Darwin"
        echo "  ✅ Home Manager"
        echo "  ❌ SystemD"
        ;;
    nixos-*)
        echo "  ✅ GUI Applications (native)"
        echo "  ✅ System Configuration" 
        echo "  ✅ SystemD"
        echo "  ✅ Home Manager"
        echo "  ✅ Full Nix Support"
        ;;
    linux-*-*)
        echo "  ⚠️  GUI Applications (limited)"
        echo "  ❌ System Configuration"
        echo "  ✅ SystemD (user)"
        echo "  ✅ Home Manager"
        echo "  ⚠️  Nix Support (standalone)"
        ;;
    wsl-*-*)
        echo "  ❌ GUI Applications"
        echo "  ❌ System Configuration"
        echo "  ⚠️  SystemD (limited)"
        echo "  ✅ Home Manager"
        echo "  ✅ Windows Integration"
        ;;
    android-*)
        echo "  ❌ GUI Applications"
        echo "  ❌ System Configuration"
        echo "  ❌ SystemD"
        echo "  ⚠️  Home Manager (limited)"
        echo "  ⚠️  Nix Support (alpha)"
        ;;
    *)
        echo "  ❌ Unsupported Platform"
        ;;
esac)
EOF
}

# メイン処理
main() {
    case "${1:-detect}" in
        detect)
            detect_platform
            ;;
        system)
            get_nix_system
            ;;
        config)
            get_nix_config
            ;;
        package-manager)
            get_package_manager
            ;;
        capabilities)
            check_capabilities
            ;;
        help)
            cat << EOF
Usage: $0 [command]

Commands:
  detect           Detect platform (default)
  system           Get Nix system architecture
  config           Get recommended Nix configuration
  package-manager  Get recommended package manager
  capabilities     Show platform capabilities
  help             Show this help

Examples:
  $0                    # darwin-aarch64
  $0 system            # aarch64-darwin
  $0 config            # darwinConfigurations.default
  $0 capabilities      # Show full capability matrix
EOF
            ;;
        *)
            echo "Unknown command: $1" >&2
            echo "Use '$0 help' for usage information." >&2
            exit 1
            ;;
    esac
}

# スクリプト直接実行時のみメイン関数を呼び出し
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

## Nix implementation 例

```nix
# lib/platform-detection.nix
{ lib, pkgs, ... }:

let
  inherit (lib) optionalString hasAttr;
  inherit (pkgs.stdenv) isDarwin isLinux hostPlatform;
  
  # プラットフォーム情報検出
  platformInfo = rec {
    # 基本的なプラットフォーム情報
    system = hostPlatform.system;
    isDarwin = isDarwin;
    isLinux = isLinux;
    
    # より詳細な検出
    isNixOS = builtins.pathExists /etc/NIXOS;
    isAndroid = builtins.getEnv "NIX_ON_DROID" != "";
    isWSL = builtins.getEnv "WSL_DISTRO_NAME" != "";
    
    # アーキテクチャ
    isAarch64 = hostPlatform.isAarch64;
    isX86_64 = hostPlatform.isx86_64;
    isI686 = hostPlatform.isi686;
    
    # ディストリビューション（可能な場合）
    linuxDistro = 
      if builtins.pathExists /etc/os-release then
        let
          osRelease = builtins.readFile /etc/os-release;
          idLine = builtins.head (builtins.filter (line: 
            lib.hasPrefix "ID=" line
          ) (lib.splitString "\n" osRelease));
          distroId = lib.removePrefix "ID=" (lib.removeSuffix "\"" (lib.removePrefix "\"" idLine));
        in distroId
      else "unknown";
    
    # プラットフォーム文字列
    platformString = 
      if isAndroid then "android"
      else if isWSL then "wsl-${linuxDistro}"
      else if isDarwin then "darwin"
      else if isNixOS then "nixos"
      else if isLinux then "linux-${linuxDistro}"
      else "unknown";
  };
  
  # 機能サポート
  capabilities = {
    hasGUI = !platformInfo.isAndroid && !platformInfo.isWSL;
    hasSystemd = platformInfo.isLinux && !platformInfo.isAndroid;
    hasHomebrew = platformInfo.isDarwin;
    hasNativePackageManager = platformInfo.isNixOS || platformInfo.isDarwin;
    canUseDocker = !platformInfo.isAndroid;
    hasSystemConfig = platformInfo.isNixOS || platformInfo.isDarwin;
    
    # Home Manager サポートレベル
    homeManagerSupport = 
      if platformInfo.isNixOS || platformInfo.isDarwin then "full"
      else if platformInfo.isLinux then "standalone"
      else if platformInfo.isAndroid then "limited"
      else "none";
  };
  
  # 推奨設定
  recommendations = {
    # パッケージマネージャー
    packageManager = 
      if platformInfo.isDarwin then "nix-darwin + homebrew"
      else if platformInfo.isNixOS then "nixos"
      else if platformInfo.isLinux then "home-manager + system-pm"
      else if platformInfo.isAndroid then "nix-on-droid"
      else "unknown";
      
    # GUI アプリケーション戦略
    guiStrategy = 
      if platformInfo.isDarwin then "homebrew-casks"
      else if platformInfo.isNixOS then "nixpkgs"
      else if platformInfo.isLinux then "nixpkgs + genericLinux"
      else "none";
      
    # ターミナル推奨
    terminalEmulator = 
      if platformInfo.isDarwin then "wezterm"
      else if capabilities.hasGUI then "alacritty"
      else "builtin";
  };

in {
  inherit platformInfo capabilities recommendations;
  
  # 条件付きヘルパー関数
  onPlatform = platform: config: 
    if platformInfo.platformString == platform then config else {};
    
  onPlatforms = platforms: config:
    if builtins.elem platformInfo.platformString platforms then config else {};
    
  onCapability = capability: config:
    if hasAttr capability capabilities && capabilities.${capability} then config else {};
    
  # プラットフォーム別パッケージフィルター
  filterPackages = packages: 
    builtins.filter (pkg: 
      # 基本的なフィルタリング例
      if platformInfo.isAndroid then
        # Android では GUI パッケージを除外
        !(hasAttr "meta" pkg && hasAttr "platforms" pkg.meta && 
          builtins.elem "x11" (pkg.meta.platforms or []))
      else true
    ) packages;
}
```

## 使用例

```bash
# プラットフォーム検出
$ ./scripts/detect-platform.sh
darwin-aarch64

# 機能確認
$ ./scripts/detect-platform.sh capabilities
Platform: darwin-aarch64
Nix System: aarch64-darwin
Package Manager: nix-darwin + homebrew

Capabilities:
  ✅ GUI Applications (via Homebrew)
  ✅ System Preferences
  ✅ Nix Darwin
  ✅ Home Manager
  ❌ SystemD

# Nix設定での自動選択
$ nix build .#$(./scripts/detect-platform.sh config)

# 条件付きビルド
$ if [[ "$(./scripts/detect-platform.sh)" == "darwin-"* ]]; then
    echo "macOS detected, using Homebrew for GUI apps"
  fi
```

この実装により、各プラットフォームで最適な設定を自動選択し、統一された開発環境を提供できます。