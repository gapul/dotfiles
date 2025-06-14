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

# バックアップ対象ファイル
declare -A DOTFILES=(
    [".zshrc"]="$HOME_DIR/.zshrc"
    [".zprofile"]="$HOME_DIR/.zprofile"
    [".gitconfig"]="$HOME_DIR/.gitconfig"
    [".condarc"]="$HOME_DIR/.condarc"
    [".claude.json"]="$HOME_DIR/.claude.json"
    [".vimrc"]="$HOME_DIR/.vimrc"
)

# バックアップディレクトリの作成
create_backup_dir() {
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_session_dir="$BACKUP_DIR/backup_$timestamp"
    
    mkdir -p "$backup_session_dir"
    echo "$backup_session_dir"
}

# ファイルのバックアップ
backup_files() {
    local backup_session_dir="$1"
    local backup_count=0
    
    log_info "ドットファイルのバックアップを開始します..."
    
    for filename in "${!DOTFILES[@]}"; do
        local source_path="${DOTFILES[$filename]}"
        local backup_path="$backup_session_dir/$filename"
        
        if [[ -e "$source_path" ]]; then
            if [[ -L "$source_path" ]]; then
                # シンボリックリンクの場合
                local link_target=$(readlink "$source_path")
                echo "$link_target" > "$backup_path.symlink_target"
                log_info "$filename (シンボリックリンク -> $link_target) をバックアップしました"
            else
                # 通常ファイルの場合
                cp "$source_path" "$backup_path"
                log_info "$filename をバックアップしました"
            fi
            ((backup_count++))
        else
            log_warning "$filename が見つかりません: $source_path"
        fi
    done
    
    return $backup_count
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
        for filename in "${!DOTFILES[@]}"; do
            local source_path="${DOTFILES[$filename]}"
            if [[ -e "$source_path" ]]; then
                echo "  $filename"
                if [[ -L "$source_path" ]]; then
                    echo "    Type: Symbolic Link"
                    echo "    Target: $(readlink "$source_path")"
                else
                    echo "    Type: Regular File"
                    echo "    Size: $(wc -c < "$source_path") bytes"
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
    
    local backups=($(find "$BACKUP_DIR" -name "backup_*" -type d | sort -r))
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        log_info "バックアップが見つかりません"
        return
    fi
    
    echo "利用可能なバックアップ:"
    for backup in "${backups[@]}"; do
        local backup_name=$(basename "$backup")
        local backup_date=${backup_name#backup_}
        local formatted_date=$(echo "$backup_date" | sed 's/_/ /')
        
        if [[ -f "$backup/backup_info.txt" ]]; then
            local file_count=$(grep "Files Backed Up:" "$backup/backup_info.txt" | cut -d: -f2 | tr -d ' ')
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
            
            local backup_session_dir=$(create_backup_dir)
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