#!/bin/bash
# nix-channel-setup.sh - Fix nix channels and search path issues

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check current nix setup
check_nix_setup() {
    log_info "=== Nix環境状態確認 ==="
    
    # Check nix installation
    if command -v nix &> /dev/null; then
        log_success "nix コマンド利用可能: $(nix --version)"
    else
        log_error "nix コマンドが見つかりません"
        return 1
    fi
    
    # Check current channels
    echo "現在のチャンネル:"
    nix-channel --list || log_warning "チャンネル一覧取得失敗"
    
    # Check NIX_PATH
    echo "NIX_PATH: ${NIX_PATH:-未設定}"
    
    # Check search paths
    echo "nix search paths:"
    nix eval --expr 'builtins.nixPath' 2>/dev/null || log_warning "検索パス取得失敗"
}

# Setup stable channel
setup_stable_channel() {
    log_info "=== 安定版チャンネル設定 ==="
    
    # Add nixpkgs stable channel
    log_info "nixpkgs安定版チャンネルを追加中..."
    nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs
    
    # Update channels
    log_info "チャンネル更新中..."
    nix-channel --update
    
    log_success "安定版チャンネル設定完了"
}

# Fix search paths
fix_search_paths() {
    log_info "=== 検索パス修正 ==="
    
    # Set NIX_PATH for current session
    export NIX_PATH="nixpkgs=channel:nixpkgs"
    
    # Add to shell configuration
    local shell_configs=(
        "$HOME/.zshrc"
        "$HOME/.bashrc"
        "$HOME/.profile"
    )
    
    for config in "${shell_configs[@]}"; do
        if [[ -f "$config" ]]; then
            if ! grep -q "NIX_PATH.*nixpkgs" "$config"; then
                log_info "$config にNIX_PATH設定を追加中..."
                echo '' >> "$config"
                echo '# Nix search path configuration' >> "$config"
                echo 'export NIX_PATH="nixpkgs=channel:nixpkgs"' >> "$config"
                log_success "$config を更新しました"
            else
                log_info "$config には既にNIX_PATH設定があります"
            fi
        fi
    done
}

# Test nix functionality
test_nix_functionality() {
    log_info "=== Nix機能テスト ==="
    
    # Test basic search
    log_info "基本検索テスト中..."
    if nix-shell -p hello --run "hello" &>/dev/null; then
        log_success "nix-shell 基本動作確認"
    else
        log_error "nix-shell 基本動作失敗"
    fi
    
    # Test package search
    log_info "パッケージ検索テスト中..."
    if echo 'with import <nixpkgs> {}; [ git ]' | nix-instantiate --eval -E - &>/dev/null; then
        log_success "パッケージ検索動作確認"
    else
        log_warning "パッケージ検索で警告"
    fi
    
    # Test specific packages for Phase 3
    log_info "Phase 3パッケージ確認中..."
    local phase3_packages=("yabai" "skhd" "sketchybar")
    
    for package in "${phase3_packages[@]}"; do
        if nix-shell -p "$package" --run "command -v $package" &>/dev/null; then
            log_success "$package 利用可能"
        else
            log_warning "$package 利用不可または設定問題"
        fi
    done
}

# Setup flake registry
setup_flake_registry() {
    log_info "=== Flakeレジストリ設定 ==="
    
    # Add nixpkgs to flake registry
    nix registry add nixpkgs github:NixOS/nixpkgs/nixpkgs-unstable
    
    log_success "Flakeレジストリ設定完了"
}

# Clean old configurations
clean_old_configs() {
    log_info "=== 古い設定クリーンアップ ==="
    
    # Remove broken symlinks in defexpr
    if [[ -d "$HOME/.nix-defexpr" ]]; then
        find "$HOME/.nix-defexpr" -xtype l -delete 2>/dev/null || true
        log_success "破損したシンボリックリンクを削除"
    fi
    
    # Clean old generations (keep last 5)
    log_info "古い世代をクリーンアップ中..."
    nix-env --delete-generations +5 2>/dev/null || log_warning "世代クリーンアップで警告"
    
    log_success "クリーンアップ完了"
}

# Verify installation
verify_installation() {
    log_info "=== インストール検証 ==="
    
    # Check channels
    echo "設定済みチャンネル:"
    nix-channel --list
    
    # Check search functionality
    log_info "検索機能テスト..."
    if nix search nixpkgs git --json | jq empty &>/dev/null; then
        log_success "nix search 動作確認"
    else
        log_warning "nix search に問題がある可能性"
    fi
    
    # Check environment
    echo "環境変数:"
    echo "  NIX_PATH: ${NIX_PATH:-未設定}"
    echo "  HOME: $HOME"
    echo "  USER: ${USER:-未設定}"
    
    log_success "検証完了"
}

# Show usage
show_usage() {
    cat << EOF
nix-channel-setup.sh - Nix チャンネルと検索パス設定ツール

使用方法:
    $0 [コマンド]

コマンド:
    check       現在の状態確認
    setup       完全セットアップ実行
    channels    チャンネル設定のみ
    paths       検索パス修正のみ
    test        機能テストのみ
    clean       古い設定クリーンアップ
    verify      設定検証
    help        このヘルプを表示

推奨実行順序:
    1. $0 check     # 現在の状態確認
    2. $0 setup     # 完全セットアップ
    3. $0 verify    # 設定検証

EOF
}

# Main function
main() {
    case "${1:-setup}" in
        "check")
            check_nix_setup
            ;;
        "setup")
            log_info "Nix環境完全セットアップ開始"
            check_nix_setup
            setup_stable_channel
            fix_search_paths
            setup_flake_registry
            test_nix_functionality
            verify_installation
            log_success "Nix環境セットアップ完了"
            echo ""
            log_info "シェルを再起動してください: exec \$SHELL"
            ;;
        "channels")
            setup_stable_channel
            ;;
        "paths")
            fix_search_paths
            ;;
        "test")
            test_nix_functionality
            ;;
        "clean")
            clean_old_configs
            ;;
        "verify")
            verify_installation
            ;;
        "help"|"-h"|"--help")
            show_usage
            ;;
        *)
            log_error "無効なコマンドです: $1"
            show_usage
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"