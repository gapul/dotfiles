#!/bin/bash
# phase3-migration.sh - Phase 3: System tools migration script
# Migrates yabai ecosystem from Homebrew to nixpkgs

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

# Configuration paths
readonly NIX_DARWIN_DIR="$HOME/.config/nix-darwin"
readonly DOTFILES_DIR="$HOME/dotfiles"
readonly BACKUP_DIR
BACKUP_DIR="$HOME/.phase3-backups/$(date +%Y%m%d_%H%M%S)"

# Check prerequisites
check_prerequisites() {
    log_info "=== Phase 3 前提条件チェック ==="
    
    # Check nix installation
    if ! command -v nix &> /dev/null; then
        log_error "nix コマンドが見つかりません"
        exit 1
    fi
    
    if ! command -v darwin-rebuild &> /dev/null; then
        log_error "darwin-rebuild コマンドが見つかりません"
        exit 1
    fi
    
    # Check current yabai installation
    if ! command -v yabai &> /dev/null; then
        log_error "yabai がインストールされていません"
        exit 1
    fi
    
    if ! command -v skhd &> /dev/null; then
        log_error "skhd がインストールされていません"
        exit 1
    fi
    
    if ! command -v sketchybar &> /dev/null; then
        log_error "sketchybar がインストールされていません"
        exit 1
    fi
    
    log_success "前提条件チェック完了"
}

# Create backup of current configuration
create_backup() {
    log_info "=== 現在の設定をバックアップ中 ==="
    
    mkdir -p "$BACKUP_DIR"
    
    # Backup yabai configuration
    if [[ -f ~/.yabairc ]]; then
        cp ~/.yabairc "$BACKUP_DIR/yabairc"
        log_success "yabai 設定をバックアップしました"
    fi
    
    # Backup skhd configuration
    if [[ -f ~/.skhdrc ]]; then
        cp ~/.skhdrc "$BACKUP_DIR/skhdrc"
        log_success "skhd 設定をバックアップしました"
    fi
    
    # Backup sketchybar configuration
    if [[ -d ~/.config/sketchybar ]]; then
        cp -r ~/.config/sketchybar "$BACKUP_DIR/sketchybar"
        log_success "sketchybar 設定をバックアップしました"
    fi
    
    # Backup current versions
    yabai --version > "$BACKUP_DIR/yabai-version.txt"
    skhd --version > "$BACKUP_DIR/skhd-version.txt"
    sketchybar --version > "$BACKUP_DIR/sketchybar-version.txt"
    
    # Backup launchd plist files
    mkdir -p "$BACKUP_DIR/launchd"
    for service in yabai skhd sketchybar; do
        if [[ -f ~/Library/LaunchAgents/homebrew.mxcl.${service}.plist ]]; then
            cp ~/Library/LaunchAgents/homebrew.mxcl.${service}.plist "$BACKUP_DIR/launchd/"
        fi
    done
    
    log_success "バックアップ完了: $BACKUP_DIR"
}

# Check nixpkgs versions
check_nixpkgs_versions() {
    log_info "=== nixpkgs バージョン確認 ==="
    
    local yabai_version
    yabai_version=$(nix search nixpkgs yabai | grep "yabai" | head -1)
    local skhd_version
    skhd_version=$(nix search nixpkgs skhd | grep "skhd" | head -1)
    local sketchybar_version
    sketchybar_version=$(nix search nixpkgs sketchybar | grep "sketchybar" | head -1)
    
    echo "利用可能なバージョン:"
    echo "  yabai: $yabai_version"
    echo "  skhd: $skhd_version"
    echo "  sketchybar: $sketchybar_version"
    
    # Compare with current versions
    echo ""
    echo "現在のバージョン:"
    echo "  yabai: $(yabai --version 2>/dev/null || echo 'Unknown')"
    echo "  skhd: $(skhd --version 2>/dev/null || echo 'Unknown')"
    echo "  sketchybar: $(sketchybar --version 2>/dev/null || echo 'Unknown')"
}

# Stop current services
stop_homebrew_services() {
    log_info "=== Homebrew サービス停止中 ==="
    
    # Stop all window management services
    for service in yabai skhd sketchybar; do
        if brew services list | grep -q "$service.*started"; then
            log_info "Stopping $service..."
            brew services stop "$service"
            log_success "$service stopped"
        fi
    done
    
    # Kill any remaining processes
    pkill -f yabai || true
    pkill -f skhd || true
    pkill -f sketchybar || true
    
    sleep 2
    log_success "全てのサービスを停止しました"
}

# Update nix-darwin configuration
update_nix_darwin_config() {
    log_info "=== nix-darwin 設定更新中 ==="
    
    local darwin_config="$NIX_DARWIN_DIR/nix/darwin.nix"
    
    # Backup current config
    cp "$darwin_config" "$BACKUP_DIR/darwin.nix.backup"
    
    # Remove commented lines and add actual packages
    sed -i.bak '/# Window management (Phase 3 migration targets)/,/# sketchybar # To be migrated from Homebrew/c\
    # Window management (migrated from Homebrew)\
    yabai\
    skhd\
    sketchybar' "$darwin_config"
    
    # Update homebrew section to remove yabai ecosystem
    sed -i.bak '/# Moving to nixpkgs in Phase 3/,/sketchybar"/d' "$darwin_config"
    
    # Clean up backup file
    rm -f "${darwin_config}.bak"
    
    log_success "nix-darwin 設定を更新しました"
}

# Configure launchd services
configure_nix_services() {
    log_info "=== nix サービス設定中 ==="
    
    local darwin_config="$NIX_DARWIN_DIR/nix/darwin.nix"
    
    # Add launchd configuration
    local launchd_config='
  # Window management services
  launchd.user.agents = {
    yabai = {
      serviceConfig = {
        ProgramArguments = [
          "${pkgs.yabai}/bin/yabai"
        ];
        RunAtLoad = true;
        KeepAlive = {
          SuccessfulExit = false;
        };
        StandardErrorPath = "${homeDirectory}/.local/logs/yabai.err.log";
        StandardOutPath = "${homeDirectory}/.local/logs/yabai.out.log";
      };
    };
    
    skhd = {
      serviceConfig = {
        ProgramArguments = [
          "${pkgs.skhd}/bin/skhd"
        ];
        RunAtLoad = true;
        KeepAlive = {
          SuccessfulExit = false;
        };
        StandardErrorPath = "${homeDirectory}/.local/logs/skhd.err.log";
        StandardOutPath = "${homeDirectory}/.local/logs/skhd.out.log";
      };
    };
    
    sketchybar = {
      serviceConfig = {
        ProgramArguments = [
          "${pkgs.sketchybar}/bin/sketchybar"
        ];
        RunAtLoad = true;
        KeepAlive = {
          SuccessfulExit = false;
        };
        StandardErrorPath = "${homeDirectory}/.local/logs/sketchybar.err.log";
        StandardOutPath = "${homeDirectory}/.local/logs/sketchybar.out.log";
      };
    };
  };'
    
    # Insert before the closing brace
    sed -i.bak '/^}$/i\
'"$launchd_config"'
' "$darwin_config"
    
    # Clean up backup
    rm -f "${darwin_config}.bak"
    
    # Create log directory
    mkdir -p "$HOME/.local/logs"
    
    log_success "launchd サービス設定を追加しました"
}

# Rebuild nix-darwin
rebuild_system() {
    log_info "=== nix-darwin 再構築中 ==="
    
    cd "$NIX_DARWIN_DIR"
    
    # Check configuration syntax
    log_info "設定構文チェック中..."
    if ! nix flake check; then
        log_error "nix-darwin 設定にエラーがあります"
        return 1
    fi
    
    # Rebuild system
    log_info "システム再構築中..."
    sudo darwin-rebuild switch --flake .
    
    log_success "nix-darwin 再構築完了"
}

# Start new services
start_nix_services() {
    log_info "=== nix サービス開始中 ==="
    
    # Services should start automatically via launchd
    sleep 3
    
    # Check if services are running
    local services_ok=true
    
    if ! pgrep -f yabai > /dev/null; then
        log_warning "yabai が起動していません"
        services_ok=false
    fi
    
    if ! pgrep -f skhd > /dev/null; then
        log_warning "skhd が起動していません"
        services_ok=false
    fi
    
    if ! pgrep -f sketchybar > /dev/null; then
        log_warning "sketchybar が起動していません"
        services_ok=false
    fi
    
    if $services_ok; then
        log_success "全てのサービスが正常に起動しました"
    else
        log_warning "一部のサービスが起動していません"
        log_info "手動でサービスを開始してください:"
        echo "  launchctl load ~/Library/LaunchAgents/org.nixos.yabai.plist"
        echo "  launchctl load ~/Library/LaunchAgents/org.nixos.skhd.plist"
        echo "  launchctl load ~/Library/LaunchAgents/org.nixos.sketchybar.plist"
    fi
}

# Verify migration
verify_migration() {
    log_info "=== 移行確認中 ==="
    
    # Check command availability
    local check_ok=true
    
    for cmd in yabai skhd sketchybar; do
        if command -v "$cmd" > /dev/null; then
            local path
            path=$(which "$cmd")
            if [[ "$path" == *"/nix/store"* ]]; then
                log_success "$cmd: $path (nix)"
            else
                log_warning "$cmd: $path (not nix)"
                check_ok=false
            fi
        else
            log_error "$cmd: コマンドが見つかりません"
            check_ok=false
        fi
    done
    
    # Check process status
    echo ""
    log_info "プロセス状態:"
    pgrep -f "(yabai|skhd|sketchybar)" || echo "  プロセスが見つかりません"
    
    if $check_ok; then
        log_success "Phase 3 移行が完了しました！"
    else
        log_warning "移行に問題があります。手動で確認してください。"
    fi
}

# Rollback function
rollback() {
    log_info "=== Phase 3 ロールバック開始 ==="
    
    # Stop nix services
    pkill -f yabai || true
    pkill -f skhd || true
    pkill -f sketchybar || true
    
    # Restore original darwin.nix
    if [[ -f "$BACKUP_DIR/darwin.nix.backup" ]]; then
        cp "$BACKUP_DIR/darwin.nix.backup" "$NIX_DARWIN_DIR/nix/darwin.nix"
        log_success "nix-darwin 設定を復元しました"
    fi
    
    # Rebuild with original config
    cd "$NIX_DARWIN_DIR"
    sudo darwin-rebuild switch --flake .
    
    # Restart homebrew services
    for service in yabai skhd sketchybar; do
        brew services start "$service"
    done
    
    log_success "ロールバック完了"
}

# Show usage
show_usage() {
    cat << EOF
phase3-migration.sh - Phase 3 システムツール移行スクリプト

使用方法:
    $0 [コマンド]

コマンド:
    check       前提条件チェック
    versions    nixpkgs バージョン確認
    backup      現在の設定をバックアップ
    migrate     完全移行実行
    verify      移行結果確認
    rollback    移行前の状態に戻す
    help        このヘルプを表示

推奨実行順序:
    1. $0 check
    2. $0 versions
    3. $0 backup
    4. $0 migrate
    5. $0 verify

EOF
}

# Main function
main() {
    case "${1:-help}" in
        "check")
            check_prerequisites
            ;;
        "versions")
            check_nixpkgs_versions
            ;;
        "backup")
            check_prerequisites
            create_backup
            ;;
        "migrate")
            check_prerequisites
            create_backup
            check_nixpkgs_versions
            echo ""
            read -p "Phase 3 移行を開始しますか？ (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                stop_homebrew_services
                update_nix_darwin_config
                configure_nix_services
                rebuild_system
                start_nix_services
                verify_migration
                log_success "Phase 3 移行完了！"
            else
                log_info "移行をキャンセルしました"
            fi
            ;;
        "verify")
            verify_migration
            ;;
        "rollback")
            echo ""
            read -p "Phase 3 移行前の状態にロールバックしますか？ (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rollback
            else
                log_info "ロールバックをキャンセルしました"
            fi
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