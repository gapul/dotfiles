#!/bin/bash

# ドットファイル管理システム - 復元スクリプト
# バックアップからドットファイルを復元します

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

# 復元対象ファイル（install.shと同期）
DOTFILES_LIST=(
    "shell/.zshrc:$HOME_DIR/.zshrc"
    "shell/.zprofile:$HOME_DIR/.zprofile"
    "terminal/starship.toml:$HOME_DIR/.config/starship.toml"
    "development/.condarc:$HOME_DIR/.condarc"
    "development/docker/config.json:$HOME_DIR/.docker/config.json"
    "editors/zed/settings.json:$HOME_DIR/.config/zed/settings.json"
    "editors/vscode/settings.json:$HOME_DIR/Library/Application Support/Code/User/settings.json"
    "wm/yabai/yabairc:$HOME_DIR/.config/yabai/yabairc"
    "wm/skhd/skhdrc:$HOME_DIR/.config/skhd/skhdrc"
)

# 利用可能なバックアップの取得
get_available_backups() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        return 1
    fi
    
    find "$BACKUP_DIR" -name "backup_*" -type d | sort -r
}

# バックアップの選択
select_backup() {
    local backups
    mapfile -t backups < <(get_available_backups)
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        log_error "利用可能なバックアップが見つかりません"
        return 1
    fi
    
    if [[ ${#backups[@]} -eq 1 ]]; then
        echo "${backups[0]}"
        return 0
    fi
    
    echo "利用可能なバックアップ:"
    for i in "${!backups[@]}"; do
        local backup="${backups[$i]}"
        local backup_name
        backup_name=$(basename "$backup")
        local backup_date=${backup_name#backup_}
        local formatted_date=${backup_date//_/ }
        
        echo "  $((i+1)). $formatted_date"
        
        if [[ -f "$backup/backup_info.txt" ]]; then
            local file_count
            file_count=$(grep "Files Backed Up:" "$backup/backup_info.txt" 2>/dev/null | cut -d: -f2 | tr -d ' ' || echo "不明")
            echo "     ($file_count files)"
        fi
    done
    
    while true; do
        echo -n "復元するバックアップを選択してください (1-${#backups[@]}): "
        read -r selection
        
        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le "${#backups[@]}" ]]; then
            echo "${backups[$((selection-1))]}"
            return 0
        else
            log_error "無効な選択です。1-${#backups[@]} の範囲で入力してください。"
        fi
    done
}

# 現在のファイルの削除（必要に応じて）
remove_current_files() {
    log_info "現在のドットファイルを削除しています..."
    
    for dotfile_entry in "${DOTFILES_LIST[@]}"; do
        # local source_path="${dotfile_entry%%:*}"  # Currently unused
        local target_path="${dotfile_entry##*:}"
        local filename
        filename=$(basename "$target_path")
        
        if [[ -e "$target_path" ]] || [[ -L "$target_path" ]]; then
            rm "$target_path"
            log_info "$filename を削除しました"
        fi
    done
}

# バックアップからファイルの復元
restore_files() {
    local backup_dir="$1"
    local restore_count=0
    
    log_info "バックアップからファイルを復元しています..."
    
    for dotfile_entry in "${DOTFILES_LIST[@]}"; do
        # local source_path="${dotfile_entry%%:*}"  # Currently unused
        local target_path="${dotfile_entry##*:}"
        local filename
        filename=$(basename "$target_path")
        local backup_path="$backup_dir/$filename"
        local symlink_path="$backup_path.symlink_target"
        
        if [[ -f "$backup_path" ]]; then
            # 通常ファイルの復元
            cp "$backup_path" "$target_path"
            log_success "$filename を復元しました"
            ((restore_count++))
        elif [[ -f "$symlink_path" ]]; then
            # シンボリックリンクの復元
            local link_target
            link_target=$(cat "$symlink_path")
            if [[ -e "$link_target" ]]; then
                ln -sf "$link_target" "$target_path"
                log_success "$filename (シンボリックリンク) を復元しました"
                ((restore_count++))
            else
                log_warning "$filename のリンク先が見つかりません: $link_target"
            fi
        else
            log_warning "$filename のバックアップが見つかりません: $backup_path"
        fi
    done
    
    return $restore_count
}

# バックアップ情報の表示
show_backup_info() {
    local backup_dir="$1"
    local info_file="$backup_dir/backup_info.txt"
    
    if [[ -f "$info_file" ]]; then
        echo "バックアップ情報:"
        cat "$info_file"
        echo
    fi
}

# 復元の確認
confirm_restore() {
    local backup_dir="$1"
    
    echo -n "このバックアップから復元しますか？ (y/N): "
    read -r confirmation
    
    case "$confirmation" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            log_info "復元をキャンセルしました"
            return 1
            ;;
    esac
}

# バックアップ一覧の表示
list_backups() {
    local backups
    mapfile -t backups < <(get_available_backups)
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        log_info "利用可能なバックアップがありません"
        return
    fi
    
    echo "利用可能なバックアップ:"
    for backup in "${backups[@]}"; do
        local backup_name
        backup_name=$(basename "$backup")
        local backup_date=${backup_name#backup_}
        local formatted_date=${backup_date//_/ }
        
        echo "  $formatted_date"
        
        if [[ -f "$backup/backup_info.txt" ]]; then
            local file_count
            file_count=$(grep "Files Backed Up:" "$backup/backup_info.txt" 2>/dev/null | cut -d: -f2 | tr -d ' ' || echo "不明")
            echo "    Files: $file_count"
        fi
        
        echo "    Path: $backup"
        echo
    done
}

# メイン処理
main() {
    case "${1:-restore}" in
        "restore")
            log_info "ドットファイルの復元を開始します"
            
            local backup_dir
            if [[ -n "$2" ]]; then
                # 特定のバックアップディレクトリが指定された場合
                backup_dir="$2"
                if [[ ! -d "$backup_dir" ]]; then
                    log_error "指定されたバックアップディレクトリが見つかりません: $backup_dir"
                    exit 1
                fi
            else
                # インタラクティブにバックアップを選択
                if ! backup_dir=$(select_backup); then
                    exit 1
                fi
            fi
            
            show_backup_info "$backup_dir"
            
            if ! confirm_restore "$backup_dir"; then
                exit 0
            fi
            
            remove_current_files
            restore_files "$backup_dir"
            local restore_count=$?
            
            if [[ $restore_count -gt 0 ]]; then
                log_success "復元が完了しました"
                log_info "$restore_count 個のファイルを復元しました"
            else
                log_warning "復元されたファイルがありません"
            fi
            ;;
        "list")
            list_backups
            ;;
        "help"|"-h"|"--help")
            echo "使用方法: $0 [command] [backup_dir]"
            echo ""
            echo "Commands:"
            echo "  restore [backup_dir]  バックアップから復元（デフォルト）"
            echo "  list                  利用可能なバックアップを一覧表示"
            echo "  help                  このヘルプを表示"
            echo ""
            echo "Examples:"
            echo "  $0                    インタラクティブに復元"
            echo "  $0 restore /path/to/backup_dir  指定したバックアップから復元"
            echo "  $0 list               バックアップ一覧を表示"
            ;;
        *)
            log_error "不明なコマンド: $1"
            echo "使用方法: $0 [restore|list|help]"
            exit 1
            ;;
    esac
}

# スクリプトが直接実行された場合のみmainを呼び出す
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi