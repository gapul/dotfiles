#!/bin/bash

# ドットファイル管理システム - バックアップスクリプト
# 現在のドットファイルを安全にバックアップします

set -e  # エラー時に停止

# 色付きメッセージ用の定数
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ログ関数
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

# 設定
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="$HOME"
BACKUP_DIR="$DOTFILES_DIR/backups"

# DEPRECATED: File deployment now managed via nix home-manager
# This list is kept for reference and migration verification only
# All dotfiles are now deployed declaratively via nix/home.nix home.file configuration

# Migration Notice: Backup functionality has been migrated to Nix-based approach
# For backups, use: nix profile backup or Time Machine
# For configuration rollback, use: home-manager generations

# shellcheck disable=SC2034
DEPRECATED_DOTFILES_LIST=(
    # MIGRATED TO: nix/home.nix home.file section
    # Files now managed via home-manager declarative configuration
    # This list is preserved for historical reference only
    "shell/.zshrc:$HOME_DIR/.zshrc"  # → ".zshrc".source = ../configs/zsh/zshrc
    "shell/.zprofile:$HOME_DIR/.zprofile"  # → ".zprofile".source = ../configs/zsh/zprofile
    "terminal/starship.toml:$HOME_DIR/.config/starship.toml"  # → ".config/starship.toml".source = ../configs/terminal/starship.toml
    # ... (See nix/home.nix for complete current list)
)

# バックアップディレクトリの作成
create_backup_dir() {
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_session_dir="$BACKUP_DIR/backup_$timestamp"
    
    mkdir -p "$backup_session_dir"
    echo "$backup_session_dir"
}

# DEPRECATED: Legacy file backup function removed
# Backup functionality has been migrated to Nix-based approach
# 
# MIGRATION NOTICE:
# - Individual file backups are no longer needed
# - home-manager provides generation-based rollback: home-manager generations
# - System-wide backups should use Time Machine or nix profile backup
# - For development snapshots, use git commits in dotfiles repository
#
# This function is preserved for compatibility but should not be used

legacy_backup_files() {
    log_warning "⚠️  DEPRECATED: This backup method is no longer supported"
    log_info "🔄 Recommended alternatives:"
    log_info "  - home-manager generations          : Rollback home-manager changes"
    log_info "  - Time Machine                     : System-wide backups"
    log_info "  - git commit in dotfiles repository : Configuration snapshots"
    log_info "  - nix profile backup                : Profile-based backups"
    
    return 0
}

# バックアップ情報の保存
save_backup_info() {
    local backup_session_dir="$1"
    local backup_count="$2"
    local info_file="$backup_session_dir/backup_info.txt"
    
    {
        echo "Dotfiles Backup Information"
        echo "=========================="
        echo "Date: $(date)"
        echo "Backup Directory: $backup_session_dir"
        echo "Files Backed Up: $backup_count"
        echo "Host: $(hostname)"
        echo "User: $(whoami)"
        echo ""
        echo "Backed up files:"
        for dotfile_entry in "${DOTFILES_LIST[@]}"; do
            # local source_path="${dotfile_entry%%:*}"  # unused variable
            local target_path="${dotfile_entry##*:}"
            local filename
            filename=$(basename "$target_path")
            if [[ -e "$target_path" ]]; then
                echo "  $filename"
                if [[ -L "$target_path" ]]; then
                    echo "    Type: Symbolic Link"
                    echo "    Target: $(readlink "$target_path")"
                else
                    echo "    Type: Regular File"
                    echo "    Size: $(wc -c < "$target_path") bytes"
                fi
            fi
        done
    } > "$info_file"
}

# バックアップ一覧の表示
list_backups() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_warning "バックアップディレクトリが見つかりません: $BACKUP_DIR"
        return
    fi
    
    local backups
    mapfile -t backups < <(find "$BACKUP_DIR" -name "backup_*" -type d | sort -r)
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        log_info "バックアップが見つかりません"
        return
    fi
    
    echo "利用可能なバックアップ:"
    for backup in "${backups[@]}"; do
        local backup_name
        backup_name=$(basename "$backup")
        local backup_date=${backup_name#backup_}
        local formatted_date
        formatted_date=${backup_date/_/ }
        
        if [[ -f "$backup/backup_info.txt" ]]; then
            local file_count
            file_count=$(grep "Files Backed Up:" "$backup/backup_info.txt" | cut -d: -f2 | tr -d ' ')
            echo "  $formatted_date ($file_count files)"
        else
            echo "  $formatted_date"
        fi
    done
}

# メイン処理
main() {
    case "${1:-backup}" in
        "backup")
            log_info "ドットファイルのバックアップを開始します"
            
            local backup_session_dir
            backup_session_dir=$(create_backup_dir)
            backup_files "$backup_session_dir"
            local backup_count=$?
            
            if [[ $backup_count -gt 0 ]]; then
                save_backup_info "$backup_session_dir" "$backup_count"
                log_success "バックアップが完了しました: $backup_session_dir"
                log_info "$backup_count 個のファイルをバックアップしました"
            else
                log_warning "バックアップするファイルが見つかりませんでした"
                rmdir "$backup_session_dir" 2>/dev/null || true
            fi
            ;;
        "list")
            list_backups
            ;;
        "help"|"-h"|"--help")
            echo "使用方法: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  backup (default)  現在のドットファイルをバックアップ"
            echo "  list             利用可能なバックアップを一覧表示"
            echo "  help             このヘルプを表示"
            ;;
        *)
            log_error "不明なコマンド: $1"
            echo "使用方法: $0 [backup|list|help]"
            exit 1
            ;;
    esac
}

# スクリプトが直接実行された場合のみmainを呼び出す
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi