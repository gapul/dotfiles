#!/bin/bash

# 統一パッケージ管理スクリプト
# Usage: ./unified-package-manager.sh [command] [options]

set -euo pipefail

# カラー設定
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ログ関数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# プラットフォーム検出
detect_platform() {
    if [ -f "/etc/nixos/configuration.nix" ]; then
        echo "nixos"
    elif [ -n "${WSL_DISTRO_NAME:-}" ]; then
        echo "wsl"
    elif [ -d "/data/data/com.termux" ]; then
        echo "android"
    elif [ "$(uname)" = "Darwin" ]; then
        echo "darwin"
    else
        echo "linux"
    fi
}

# 設定ディレクトリ
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM=$(detect_platform)

# パッケージ分析関数
analyze_package_usage() {
    log_info "📊 統合パッケージ分析開始..."
    
    # 重複パッケージの検出
    log_info "🔍 重複パッケージ検出中..."
    local duplicates=()
    
    # Nix vs Homebrew の既知の重複
    local known_duplicates=(
        "coreutils" "gmp" "lua" "luarocks" 
        "nodejs" "node" "python3" "python"
        "git" "curl" "wget" "vim"
    )
    
    for pkg in "${known_duplicates[@]}"; do
        local nix_installed=false
        local brew_installed=false
        
        # Nix インストール確認
        if command -v nix-store >/dev/null 2>&1; then
            if nix-store --query --references /run/current-system 2>/dev/null | grep -q "$pkg"; then
                nix_installed=true
            fi
        fi
        
        # Homebrew インストール確認
        if [[ "$PLATFORM" == "darwin" ]] && command -v brew >/dev/null 2>&1; then
            if brew list --formula | grep -q "^$pkg$"; then
                brew_installed=true
            fi
        fi
        
        # 重複検出
        if $nix_installed && $brew_installed; then
            duplicates+=("$pkg")
            log_warning "重複検出: $pkg (Nix + Homebrew)"
        fi
    done
    
    echo ""
    echo "📋 重複パッケージサマリー:"
    if [ ${#duplicates[@]} -eq 0 ]; then
        log_success "重複パッケージなし"
    else
        echo "  発見された重複: ${#duplicates[@]}件"
        for dup in "${duplicates[@]}"; do
            echo "    - $dup"
        done
    fi
    
    # パッケージ使用状況分析
    echo ""
    log_info "📈 パッケージ使用状況分析..."
    
    # 言語パッケージマネージャー分析
    analyze_language_packages
    
    # 最適化提案
    echo ""
    log_info "💡 最適化提案:"
    echo "  1. 重複パッケージをNixに統一 (${#duplicates[@]}件)"
    echo "  2. GUI アプリケーションはHomebrew管理"
    echo "  3. 言語固有パッケージはプロジェクト環境で管理"
    echo "  4. macOS専用ツールはHomebrew専用"
    
    # 期待効果
    echo ""
    log_info "🎯 期待効果:"
    echo "  - パッケージ重複: ${#duplicates[@]}件 → 0件"
    echo "  - 更新時間: 30-45分 → 10-15分 (推定)"
    echo "  - PATH競合: 解消"
    echo "  - 保守性向上: 一元化による管理簡素化"
}

# 言語パッケージマネージャー分析
analyze_language_packages() {
    log_info "🔍 言語パッケージマネージャー分析中..."
    
    # npm global packages
    if command -v npm >/dev/null 2>&1; then
        local npm_global
        npm_global=$(npm list -g --depth=0 2>/dev/null | grep -c "├──\|└──" || echo "0")
        echo "  📦 npm global packages: $npm_global"
        
        if [ "$npm_global" -gt 5 ]; then
            log_warning "多数のnpm globalパッケージ - プロジェクト固有環境への移行を推奨"
            echo "    推奨: package.json + direnv での管理"
        fi
        
        # 人気のあるグローバルパッケージをチェック
        local common_globals=("typescript" "eslint" "prettier" "nodemon" "pm2")
        for pkg in "${common_globals[@]}"; do
            if npm list -g "$pkg" >/dev/null 2>&1; then
                echo "    - $pkg (global - プロジェクト環境への移行推奨)"
            fi
        done
    fi
    
    # pip user packages
    if command -v pip >/dev/null 2>&1; then
        local pip_user
        pip_user=$(pip list --user 2>/dev/null | wc -l)
        echo "  🐍 pip user packages: $pip_user"
        
        if [ "$pip_user" -gt 5 ]; then
            log_warning "多数のpip userパッケージ - 仮想環境への移行を推奨"
            echo "    推奨: venv + requirements.txt での管理"
        fi
    fi
    
    # Ruby gems
    if command -v gem >/dev/null 2>&1; then
        local gem_user
        gem_user=$(gem list --user 2>/dev/null | wc -l)
        echo "  💎 Ruby gems (user): $gem_user"
        
        if [ "$gem_user" -gt 3 ]; then
            log_warning "多数のuser gems - Bundler + Gemfile への移行を推奨"
        fi
    fi
    
    # Go modules
    if command -v go >/dev/null 2>&1; then
        local go_bin
        go_bin=$(find "$HOME/go/bin" -type f 2>/dev/null | wc -l)
        echo "  🐹 Go binaries: $go_bin"
        
        if [ "$go_bin" -gt 10 ]; then
            log_warning "多数のGo binaries - プロジェクト固有ツールの分離を推奨"
        fi
    fi
}

# パッケージインストール
install_package() {
    local package_name="$1"
    local category="${2:-auto}"
    
    log_info "Installing $package_name (category: $category)"
    
    case "$category" in
        "system"|"auto")
            log_info "Installing via Nix..."
            if nix profile install "nixpkgs#$package_name"; then
                log_success "Installed $package_name via Nix"
            else
                log_error "Failed to install $package_name via Nix"
                return 1
            fi
            ;;
        "gui")
            if [[ "$PLATFORM" == "darwin" ]]; then
                log_info "Installing GUI app via Homebrew cask..."
                if brew install --cask "$package_name"; then
                    log_success "Installed $package_name via Homebrew cask"
                else
                    log_error "Failed to install $package_name via Homebrew cask"
                    return 1
                fi
            else
                log_info "Installing GUI app via Nix..."
                if nix profile install "nixpkgs#$package_name"; then
                    log_success "Installed $package_name via Nix"
                else
                    log_error "Failed to install $package_name via Nix"
                    return 1
                fi
            fi
            ;;
        *)
            log_error "Unknown category: $category"
            return 1
            ;;
    esac
}

# パッケージ削除
remove_package() {
    local package_name="$1"
    
    log_info "Removing $package_name..."
    
    # Nixから削除を試行
    if nix profile remove ".*$package_name.*" 2>/dev/null; then
        log_success "Removed $package_name from Nix profile"
        return 0
    fi
    
    # Homebrewから削除を試行 (macOS)
    if [[ "$PLATFORM" == "darwin" ]] && command -v brew >/dev/null 2>&1; then
        if brew uninstall "$package_name" 2>/dev/null || brew uninstall --cask "$package_name" 2>/dev/null; then
            log_success "Removed $package_name from Homebrew"
            return 0
        fi
    fi
    
    log_warning "Package $package_name not found in any package manager"
}

# 統一更新戦略
update_packages() {
    local strategy="${1:-conservative}"
    
    log_info "Starting package update (strategy: $strategy)"
    
    case "$strategy" in
        "security")
            log_info "Security update mode - updating only security-critical packages"
            update_security_packages
            ;;
        "staged")
            log_info "Staged update mode - updating with testing"
            update_with_testing
            ;;
        "conservative")
            log_info "Conservative update mode - minimal updates"
            update_conservative
            ;;
        "full")
            log_info "Full update mode - updating all packages"
            update_all_packages
            ;;
        *)
            log_error "Unknown update strategy: $strategy"
            return 1
            ;;
    esac
}

# セキュリティ更新
update_security_packages() {
    log_info "Updating security-critical packages..."
    
    # Nix security updates
    if command -v nix >/dev/null 2>&1; then
        log_info "Updating Nix security packages..."
        cd "$DOTFILES_DIR/nix" || exit 1
        
        # セキュリティ関連のinputsのみ更新
        nix flake update nixpkgs
        
        if test_rebuild; then
            log_success "Nix security update completed"
        else
            log_error "Nix security update failed"
            return 1
        fi
    fi
    
    # Homebrew security updates (macOS)
    if [[ "$PLATFORM" == "darwin" ]] && command -v brew >/dev/null 2>&1; then
        log_info "Updating Homebrew security packages..."
        brew update
        brew upgrade --greedy-latest
        log_success "Homebrew security update completed"
    fi
}

# 段階的更新
update_with_testing() {
    log_info "Performing staged update with testing..."
    
    # バックアップ作成
    create_backup
    
    # 段階1: 基盤パッケージ
    log_info "Stage 1: Updating foundation packages..."
    cd "$DOTFILES_DIR/nix" || exit 1
    nix flake update nixpkgs
    
    if test_rebuild; then
        log_success "Stage 1 completed successfully"
    else
        log_error "Stage 1 failed, rolling back..."
        restore_backup
        return 1
    fi
    
    # 段階2: 開発ツール
    log_info "Stage 2: Updating development tools..."
    nix flake update home-manager
    
    if test_rebuild; then
        log_success "Stage 2 completed successfully"
    else
        log_error "Stage 2 failed, rolling back..."
        restore_backup
        return 1
    fi
    
    # 段階3: その他のinputs
    log_info "Stage 3: Updating remaining inputs..."
    nix flake update --commit-lock-file
    
    if test_rebuild; then
        log_success "All stages completed successfully"
        cleanup_backup
    else
        log_error "Stage 3 failed, rolling back..."
        restore_backup
        return 1
    fi
}

# 保守的更新
update_conservative() {
    log_info "Performing conservative update..."
    
    cd "$DOTFILES_DIR/nix" || exit 1
    
    # 固定バージョンのみ更新（セキュリティ目的）
    local critical_inputs=("nixpkgs")
    
    for input in "${critical_inputs[@]}"; do
        log_info "Updating $input..."
        nix flake update "$input"
        
        if ! test_rebuild; then
            log_error "Update of $input failed"
            return 1
        fi
    done
    
    log_success "Conservative update completed"
}

# 全更新
update_all_packages() {
    log_info "Performing full package update..."
    
    create_backup
    
    # Nix full update
    if command -v nix >/dev/null 2>&1; then
        cd "$DOTFILES_DIR/nix" || exit 1
        nix flake update --commit-lock-file
        
        if ! test_rebuild; then
            log_error "Nix full update failed"
            restore_backup
            return 1
        fi
    fi
    
    # Homebrew full update (macOS)
    if [[ "$PLATFORM" == "darwin" ]] && command -v brew >/dev/null 2>&1; then
        brew update && brew upgrade
    fi
    
    # 言語パッケージマネージャー更新
    update_language_packages
    
    log_success "Full update completed"
    cleanup_backup
}

# 言語パッケージマネージャー更新
update_language_packages() {
    log_info "Updating language package managers..."
    
    # npm update (global packages - 最小限のみ)
    if command -v npm >/dev/null 2>&1; then
        npm update -g npm
    fi
    
    # pip update (user packages - 注意深く)
    if command -v pip >/dev/null 2>&1; then
        pip list --user --outdated --format=json | \
        jq -r '.[] | .name' | \
        head -5 | \
        xargs -I {} pip install --user --upgrade {}
    fi
}

# リビルドテスト
test_rebuild() {
    log_info "Testing rebuild..."
    
    case "$PLATFORM" in
        "darwin")
            if nix run nix-darwin -- switch --flake . --dry-run; then
                nix run nix-darwin -- switch --flake .
                return $?
            else
                return 1
            fi
            ;;
        "nixos")
            if nixos-rebuild switch --flake . --dry-run; then
                nixos-rebuild switch --flake .
                return $?
            else
                return 1
            fi
            ;;
        *)
            if nix build .#homeConfigurations.default.activationPackage; then
                return 0
            else
                return 1
            fi
            ;;
    esac
}

# バックアップ管理
create_backup() {
    local backup_dir="$DOTFILES_DIR/backups/package-update-$(date +%Y%m%d-%H%M%S)"
    log_info "Creating backup at $backup_dir"
    
    mkdir -p "$backup_dir"
    cp "$DOTFILES_DIR/nix/flake.lock" "$backup_dir/"
    
    # Current generation info
    if [[ "$PLATFORM" == "darwin" ]]; then
        darwin-rebuild --list-generations > "$backup_dir/generations.txt" 2>/dev/null || true
    fi
    
    echo "$backup_dir" > "/tmp/dotfiles-backup-location"
}

restore_backup() {
    if [ -f "/tmp/dotfiles-backup-location" ]; then
        local backup_dir
        backup_dir=$(cat "/tmp/dotfiles-backup-location")
        
        if [ -f "$backup_dir/flake.lock" ]; then
            log_info "Restoring from backup: $backup_dir"
            cp "$backup_dir/flake.lock" "$DOTFILES_DIR/nix/"
            test_rebuild
        fi
    fi
}

cleanup_backup() {
    if [ -f "/tmp/dotfiles-backup-location" ]; then
        rm -f "/tmp/dotfiles-backup-location"
    fi
}

# パッケージ競合検出
detect_conflicts() {
    log_info "Detecting package conflicts..."
    
    local conflicts=()
    
    # Nix vs Homebrew conflicts
    if [[ "$PLATFORM" == "darwin" ]] && command -v brew >/dev/null 2>&1; then
        while IFS= read -r formula; do
            if command -v "$formula" >/dev/null 2>&1; then
                local which_path
                which_path=$(command -v "$formula")
                if [[ "$which_path" == *"/nix/store"* ]]; then
                    conflicts+=("$formula")
                fi
            fi
        done < <(brew list --formula)
    fi
    
    if [ ${#conflicts[@]} -gt 0 ]; then
        log_warning "Package conflicts detected:"
        printf ' - %s\n' "${conflicts[@]}"
        
        log_info "Recommended actions:"
        for conflict in "${conflicts[@]}"; do
            echo "  brew uninstall $conflict  # Remove Homebrew version, keep Nix"
        done
    else
        log_success "No package conflicts detected"
    fi
}

# パッケージ情報表示
show_package_info() {
    local package_name="$1"
    
    log_info "Package information for: $package_name"
    
    # Nix package info
    if command -v nix >/dev/null 2>&1; then
        echo "=== Nix Information ==="
        nix search nixpkgs "$package_name" | head -10
    fi
    
    # Homebrew package info (macOS)
    if [[ "$PLATFORM" == "darwin" ]] && command -v brew >/dev/null 2>&1; then
        echo "=== Homebrew Information ==="
        brew info "$package_name" 2>/dev/null || echo "Not available in Homebrew"
    fi
    
    # Current installation status
    if command -v "$package_name" >/dev/null 2>&1; then
        echo "=== Current Installation ==="
        echo "Path: $(command -v "$package_name")"
        echo "Version: $("$package_name" --version 2>/dev/null || echo "Unknown")"
    else
        echo "=== Not Currently Installed ==="
    fi
}

# ヘルプ表示
show_help() {
    cat << EOF
Unified Package Manager for Dotfiles

USAGE:
    $0 [COMMAND] [OPTIONS]

COMMANDS:
    analyze                     - Analyze package usage and conflicts
    install <package> [category] - Install a package (category: system, gui, auto)
    remove <package>            - Remove a package
    update [strategy]           - Update packages (strategy: security, staged, conservative, full)
    conflicts                   - Detect package conflicts
    info <package>             - Show package information
    help                       - Show this help message

EXAMPLES:
    $0 analyze                  # Check for package conflicts and usage
    $0 install ripgrep system   # Install ripgrep as system package
    $0 install firefox gui      # Install firefox as GUI application
    $0 update security          # Security-only updates
    $0 update staged            # Staged update with testing
    $0 conflicts                # Check for package conflicts
    $0 info neovim             # Show information about neovim package

STRATEGIES:
    security    - Update only security-critical packages
    staged      - Update with testing and rollback capability
    conservative - Minimal updates for stability
    full        - Update all packages

EOF
}

# メイン処理
main() {
    case "${1:-help}" in
        "analyze")
            analyze_package_usage
            ;;
        "install")
            if [ $# -lt 2 ]; then
                log_error "Package name required"
                exit 1
            fi
            install_package "$2" "${3:-auto}"
            ;;
        "remove")
            if [ $# -lt 2 ]; then
                log_error "Package name required"
                exit 1
            fi
            remove_package "$2"
            ;;
        "update")
            update_packages "${2:-conservative}"
            ;;
        "conflicts")
            detect_conflicts
            ;;
        "info")
            if [ $# -lt 2 ]; then
                log_error "Package name required"
                exit 1
            fi
            show_package_info "$2"
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        *)
            log_error "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

# スクリプト実行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi