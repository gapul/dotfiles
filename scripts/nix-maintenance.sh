#!/bin/bash
# nix-maintenance.sh - Comprehensive nix system maintenance script
# Provides garbage collection, rollback, optimization, and system health checks

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

# Check if nix is properly installed
check_nix_installation() {
    if ! command -v nix &> /dev/null; then
        log_error "nix コマンドが見つかりません。nixがインストールされているか確認してください。"
        exit 1
    fi
    
    if ! command -v darwin-rebuild &> /dev/null; then
        log_error "darwin-rebuild コマンドが見つかりません。nix-darwinがインストールされているか確認してください。"
        exit 1
    fi
    
    if ! command -v home-manager &> /dev/null; then
        log_error "home-manager コマンドが見つかりません。home-managerがインストールされているか確認してください。"
        exit 1
    fi
}

# Show system status
show_system_status() {
    log_info "=== nix システム状態 ==="
    
    echo "nix バージョン: $(nix --version)"
    echo "nix-darwin 世代数: $(darwin-rebuild --list-generations | wc -l)"
    echo "home-manager 世代数: $(home-manager generations | wc -l)"
    
    # Disk usage
    local store_size
    store_size=$(du -sh /nix/store 2>/dev/null | cut -f1 || echo "不明")
    echo "nix store サイズ: $store_size"
    
    # Dead links
    local dead_links
    dead_links=$(nix store gc --dry-run 2>&1 | grep -E '[0-9]+ store paths deleted' | grep -oE '[0-9]+' || echo "0")
    echo "削除可能なストアパス: $dead_links"
    
    echo ""
}

# Garbage collection with safety checks
run_garbage_collection() {
    log_info "=== ガーベージコレクション実行 ==="
    
    # Show what would be deleted
    log_info "削除予定のパスを確認中..."
    nix store gc --dry-run
    
    echo ""
    read -p "ガーベージコレクションを実行しますか？ (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "ガーベージコレクション開始..."
        local before_size
        before_size=$(du -sh /nix/store 2>/dev/null | cut -f1 || echo "不明")
        
        nix store gc
        
        local after_size
        after_size=$(du -sh /nix/store 2>/dev/null | cut -f1 || echo "不明")
        log_success "ガーベージコレクション完了"
        log_info "ストアサイズ: $before_size → $after_size"
    else
        log_info "ガーベージコレクションをキャンセルしました"
    fi
}

# Optimize nix store
optimize_store() {
    log_info "=== nix store 最適化 ==="
    
    log_info "ストア最適化を開始..."
    nix store optimise
    log_success "ストア最適化完了"
}

# Show available generations
list_generations() {
    log_info "=== 利用可能な世代一覧 ==="
    
    echo "📍 nix-darwin 世代:"
    darwin-rebuild --list-generations | tail -10
    
    echo ""
    echo "🏠 home-manager 世代:"
    home-manager generations | tail -10
}

# Rollback to previous generation
rollback_system() {
    local system_type="${1:-}"
    
    case "$system_type" in
        "darwin"|"system")
            log_info "=== nix-darwin ロールバック ==="
            darwin-rebuild --list-generations | tail -5
            echo ""
            read -p "ロールバック先の世代ID を入力してください: " -r generation_id
            
            if [[ -n "$generation_id" ]]; then
                log_info "nix-darwin を世代 $generation_id にロールバック中..."
                sudo darwin-rebuild --rollback --switch-generation "$generation_id"
                log_success "nix-darwin ロールバック完了"
            fi
            ;;
        "home"|"user")
            log_info "=== home-manager ロールバック ==="
            home-manager generations | tail -5
            echo ""
            read -p "ロールバック先のパスを入力してください: " -r generation_path
            
            if [[ -n "$generation_path" ]]; then
                log_info "home-manager を指定世代にロールバック中..."
                "$generation_path/activate"
                log_success "home-manager ロールバック完了"
            fi
            ;;
        *)
            log_error "無効なシステムタイプです。'darwin' または 'home' を指定してください。"
            exit 1
            ;;
    esac
}

# Health check
health_check() {
    log_info "=== システムヘルスチェック ==="
    
    local issues=0
    
    # Check nix daemon
    if launchctl list | grep -q "org.nixos.nix-daemon"; then
        log_success "nix daemon 実行中"
    else
        log_warning "nix daemon が実行されていません"
        ((issues++))
    fi
    
    # Check store corruption
    log_info "ストア整合性チェック中..."
    if nix store verify --all 2>/dev/null; then
        log_success "ストア整合性OK"
    else
        log_warning "ストアに問題が検出されました"
        ((issues++))
    fi
    
    # Check disk space
    local available_space
    available_space=$(df -h /nix | tail -1 | awk '{print $4}' | tr -d 'Gi')
    if [[ "$available_space" -lt 5 ]]; then
        log_warning "ディスク容量が不足しています (残り: ${available_space}GB)"
        ((issues++))
    else
        log_success "ディスク容量OK (残り: ${available_space}GB)"
    fi
    
    if [[ $issues -eq 0 ]]; then
        log_success "システムヘルスチェック完了: 問題なし"
    else
        log_warning "システムヘルスチェック完了: $issues 件の問題が検出されました"
    fi
}

# Update system and user environments
update_system() {
    log_info "=== システム更新 ==="
    
    # Update flake inputs
    log_info "flake inputs を更新中..."
    if [[ -f ~/.config/nix-darwin/flake.nix ]]; then
        cd ~/.config/nix-darwin
        nix flake update
        log_success "flake inputs 更新完了"
    fi
    
    # Rebuild darwin
    log_info "nix-darwin 再構築中..."
    sudo darwin-rebuild switch --flake ~/.config/nix-darwin
    log_success "nix-darwin 再構築完了"
    
    # Rebuild home-manager
    log_info "home-manager 再構築中..."
    home-manager switch --flake ~/.config/nix-darwin
    log_success "home-manager 再構築完了"
}

# Create backup of current configuration
create_backup() {
    local backup_dir
    backup_dir="$HOME/.nix-backups/$(date +%Y%m%d_%H%M%S)"
    
    log_info "=== 設定バックアップ作成 ==="
    log_info "バックアップ先: $backup_dir"
    
    mkdir -p "$backup_dir"
    
    # Backup nix-darwin configuration
    if [[ -d ~/.config/nix-darwin ]]; then
        cp -r ~/.config/nix-darwin "$backup_dir/nix-darwin"
        log_success "nix-darwin 設定をバックアップしました"
    fi
    
    # Backup current generation info
    darwin-rebuild --list-generations > "$backup_dir/darwin-generations.txt"
    home-manager generations > "$backup_dir/home-generations.txt"
    
    # Backup important nix files
    cp /etc/nix/nix.conf "$backup_dir/nix.conf" 2>/dev/null || true
    
    log_success "バックアップ作成完了: $backup_dir"
}

# Show usage information
show_usage() {
    cat << EOF
nix-maintenance.sh - nix システムメンテナンスツール

使用方法:
    $0 [コマンド] [オプション]

コマンド:
    status      システム状態を表示
    gc          ガーベージコレクション実行
    optimize    ストア最適化
    generations 世代一覧表示
    rollback    指定世代にロールバック
                --darwin: nix-darwin ロールバック
                --home:   home-manager ロールバック
    health      システムヘルスチェック
    update      システム・flake更新
    backup      現在の設定をバックアップ
    maintenance 完全メンテナンス実行 (gc + optimize + health)
    help        このヘルプを表示

例:
    $0 status
    $0 gc
    $0 rollback --darwin
    $0 maintenance

EOF
}

# Full maintenance routine
run_full_maintenance() {
    log_info "=== 完全メンテナンス開始 ==="
    
    check_nix_installation
    show_system_status
    
    echo ""
    read -p "完全メンテナンスを実行しますか？ (バックアップ → ガーベージコレクション → 最適化 → ヘルスチェック) (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        create_backup
        run_garbage_collection
        optimize_store
        health_check
        log_success "完全メンテナンス完了"
    else
        log_info "メンテナンスをキャンセルしました"
    fi
}

# Main function
main() {
    case "${1:-help}" in
        "status")
            check_nix_installation
            show_system_status
            ;;
        "gc")
            check_nix_installation
            run_garbage_collection
            ;;
        "optimize")
            check_nix_installation
            optimize_store
            ;;
        "generations")
            check_nix_installation
            list_generations
            ;;
        "rollback")
            check_nix_installation
            case "${2:-}" in
                "--darwin"|"--system")
                    rollback_system "darwin"
                    ;;
                "--home"|"--user")
                    rollback_system "home"
                    ;;
                *)
                    log_error "ロールバックタイプを指定してください: --darwin または --home"
                    exit 1
                    ;;
            esac
            ;;
        "health")
            check_nix_installation
            health_check
            ;;
        "update")
            check_nix_installation
            update_system
            ;;
        "backup")
            check_nix_installation
            create_backup
            ;;
        "maintenance")
            run_full_maintenance
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

# Execute main function with all arguments
main "$@"