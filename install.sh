#!/bin/bash

# ドットファイル管理システム - インストールスクリプト
# このスクリプトは既存のドットファイルをバックアップし、
# configs/ディレクトリからシンボリックリンクを作成します

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

# 現在のディレクトリ（dotfiles リポジトリのパス）
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="$HOME"
BACKUP_DIR="$DOTFILES_DIR/backups"
CONFIG_DIR="$DOTFILES_DIR/configs"

# 管理対象ドットファイルの定義
# format: "source_path:target_path"
DOTFILES_LIST=(
    # Phase 1: 基本設定（必須）
    "shell/.zshrc:$HOME_DIR/.zshrc"
    "shell/.zprofile:$HOME_DIR/.zprofile"
    "terminal/starship.toml:$HOME_DIR/.config/starship.toml"
    
    # Phase 2: 開発ツール設定
    "development/.condarc:$HOME_DIR/.condarc"
    "development/docker/config.json:$HOME_DIR/.docker/config.json"
    
    # Phase 3: エディター設定（任意）
    "editors/zed/settings.json:$HOME_DIR/.config/zed/settings.json"
    "editors/vscode/settings.json:$HOME_DIR/Library/Application Support/Code/User/settings.json"
    
    # Phase 4: ウィンドウマネージャー設定（macOS限定・任意）
    "wm/yabai/yabairc:$HOME_DIR/.config/yabai/yabairc"
    "wm/skhd/skhdrc:$HOME_DIR/.config/skhd/skhdrc"
)

# バックアップディレクトリの作成
create_backup_dir() {
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_session_dir="$BACKUP_DIR/backup_$timestamp"
    
    if [[ ! -d "$backup_session_dir" ]]; then
        mkdir -p "$backup_session_dir"
        log_info "バックアップディレクトリを作成しました: $backup_session_dir" >&2
    fi
    
    echo "$backup_session_dir"
}

# 既存ファイルのバックアップ
backup_existing_files() {
    local backup_session_dir="$1"
    log_info "既存のドットファイルをバックアップしています..."
    
    for dotfile_entry in "${DOTFILES_LIST[@]}"; do
        local source_path="${dotfile_entry%%:*}"
        local target_path="${dotfile_entry##*:}"
        
        if [[ -e "$target_path" ]] || [[ -L "$target_path" ]]; then
            local backup_path="$backup_session_dir/$(basename "$target_path")"
            
            if [[ -L "$target_path" ]]; then
                log_warning "$(basename "$target_path") は既にシンボリックリンクです"
                echo "$(readlink "$target_path")" > "$backup_path.symlink_target"
                rm "$target_path"
            else
                mv "$target_path" "$backup_path"
                log_info "$(basename "$target_path") をバックアップしました"
            fi
        fi
    done
}

# シンボリックリンクの作成
create_symlinks() {
    log_info "シンボリックリンクを作成しています..."
    
    for dotfile_entry in "${DOTFILES_LIST[@]}"; do
        local source_path="${dotfile_entry%%:*}"
        local target_path="${dotfile_entry##*:}"
        local full_source_path="$CONFIG_DIR/$source_path"
        
        if [[ ! -f "$full_source_path" ]]; then
            log_warning "ソースファイルが見つかりません: $full_source_path"
            continue
        fi
        
        # ターゲットディレクトリが存在しない場合は作成
        local target_dir=$(dirname "$target_path")
        if [[ ! -d "$target_dir" ]]; then
            mkdir -p "$target_dir"
        fi
        
        # シンボリックリンクを作成
        ln -sf "$full_source_path" "$target_path"
        log_success "$(basename "$target_path") のシンボリックリンクを作成しました"
    done
}

# メイン処理
main() {
    log_info "ドットファイル管理システムのインストールを開始します"
    log_info "Dotfiles directory: $DOTFILES_DIR"
    
    # 必要なディレクトリの存在確認
    if [[ ! -d "$CONFIG_DIR" ]]; then
        log_error "configs ディレクトリが見つかりません: $CONFIG_DIR"
        exit 1
    fi
    
    # バックアップの実行
    local backup_session_dir=$(create_backup_dir)
    backup_existing_files "$backup_session_dir"
    
    # シンボリックリンクの作成
    create_symlinks
    
    log_success "ドットファイル管理システムのインストールが完了しました"
    log_info "バックアップは以下に保存されました: $backup_session_dir"
    
    # インストール後の確認
    echo
    log_info "作成されたシンボリックリンクの確認:"
    
    # 個別にシンボリックリンクを確認
    symlinks_found=false
    if [[ -L "$HOME_DIR/.zshrc" ]]; then
        echo "  .zshrc -> $(readlink "$HOME_DIR/.zshrc")"
        symlinks_found=true
    fi
    if [[ -L "$HOME_DIR/.zprofile" ]]; then
        echo "  .zprofile -> $(readlink "$HOME_DIR/.zprofile")"
        symlinks_found=true
    fi
    if [[ -L "$HOME_DIR/.config/starship.toml" ]]; then
        echo "  starship.toml -> $(readlink "$HOME_DIR/.config/starship.toml")"
        symlinks_found=true
    fi
    if [[ -L "$HOME_DIR/.condarc" ]]; then
        echo "  .condarc -> $(readlink "$HOME_DIR/.condarc")"
        symlinks_found=true
    fi
    if [[ -L "$HOME_DIR/.docker/config.json" ]]; then
        echo "  docker/config.json -> $(readlink "$HOME_DIR/.docker/config.json")"
        symlinks_found=true
    fi
    if [[ -L "$HOME_DIR/.config/zed/settings.json" ]]; then
        echo "  zed/settings.json -> $(readlink "$HOME_DIR/.config/zed/settings.json")"
        symlinks_found=true
    fi
    if [[ -L "$HOME_DIR/Library/Application Support/Code/User/settings.json" ]]; then
        echo "  vscode/settings.json -> $(readlink "$HOME_DIR/Library/Application Support/Code/User/settings.json")"
        symlinks_found=true
    fi
    if [[ -L "$HOME_DIR/.config/yabai/yabairc" ]]; then
        echo "  yabai/yabairc -> $(readlink "$HOME_DIR/.config/yabai/yabairc")"
        symlinks_found=true
    fi
    if [[ -L "$HOME_DIR/.config/skhd/skhdrc" ]]; then
        echo "  skhd/skhdrc -> $(readlink "$HOME_DIR/.config/skhd/skhdrc")"
        symlinks_found=true
    fi
    
    if [[ "$symlinks_found" != true ]]; then
        log_warning "シンボリックリンクが見つかりませんでした"
    fi
}

# スクリプトが直接実行された場合のみmainを呼び出す
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi