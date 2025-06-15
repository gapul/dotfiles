#!/bin/bash

# ドットファイル管理システム - インストールスクリプト
# このスクリプトは既存のドットファイルをバックアップし、
# configs/ディレクトリからシンボリックリンクを作成します

# 共通ユーティリティ関数を読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# デバッグモード用の環境変数
DEBUG=${DEBUG:-false}

# エラーハンドラー
error_handler() {
    local line_number=$1
    local error_code=$2
    local command="$3"
    
    log_error "Script failed at line $line_number with exit code $error_code"
    log_error "Failed command: $command"
    log_error "Dotfiles installation was interrupted"
    
    # 現在の状態を表示
    log_info "Current state check:"
    if [[ -d "$BACKUP_DIR" ]]; then
        local latest_backup
        latest_backup=$(find "$BACKUP_DIR" -maxdepth 1 -type d ! -path "$BACKUP_DIR" -exec stat -f "%m %N" {} \; 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2- | xargs basename 2>/dev/null || echo "")
        if [[ -n "$latest_backup" ]]; then
            log_info "Latest backup available: $BACKUP_DIR/$latest_backup"
        fi
    fi
    
    exit "$error_code"
}

# エラーハンドラーを設定
trap 'error_handler ${LINENO} $? "$BASH_COMMAND"' ERR

# 現在のディレクトリ（dotfiles リポジトリのパス）
DOTFILES_DIR="$(get_dotfiles_dir)"
HOME_DIR="$HOME"
BACKUP_DIR="$DOTFILES_DIR/backups"
CONFIG_DIR="$DOTFILES_DIR/configs"

# オプション設定
FORCE_MODE=false
CLEANUP_BACKUPS=false
SHOW_BACKUPS=false

# コマンドライン引数の処理
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE_MODE=true
            shift
            ;;
        --cleanup-backups)
            CLEANUP_BACKUPS=true
            shift
            ;;
        --list-backups)
            SHOW_BACKUPS=true
            shift
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        -h|--help)
            echo "使用方法: $0 [オプション]"
            echo "オプション:"
            echo "  -f, --force          既存の設定を強制的に上書き"
            echo "  --cleanup-backups    古いバックアップ（7日以上前）を削除"
            echo "  --list-backups       既存のバックアップ一覧を表示"
            echo "  --debug              デバッグ情報を表示"
            echo "  -h, --help           このヘルプを表示"
            echo ""
            echo "環境変数:"
            echo "  DEBUG=true           デバッグモードを有効化"
            exit 0
            ;;
        *)
            log_error "不明なオプション: $1"
            exit 1
            ;;
    esac
done

# 管理対象ドットファイルの定義
# format: "source_path:target_path"
DOTFILES_LIST=(
    # Phase 1: 基本設定（必須）
    "zsh/zshrc:$HOME_DIR/.zshrc"
    "zsh/zprofile:$HOME_DIR/.zprofile"
    "terminal/starship.toml:$HOME_DIR/.config/starship.toml"
    "terminal/wezterm.lua:$HOME_DIR/.config/wezterm/wezterm.lua"
    "terminal/tmux.conf:$HOME_DIR/.tmux.conf"
    
    # Phase 2: 開発ツール設定
    "development/.condarc:$HOME_DIR/.condarc"
    "development/docker/config.json:$HOME_DIR/.docker/config.json"
    "development/docker/daemon.json:$HOME_DIR/.docker/daemon.json"
    "cli/gh/config.yml:$HOME_DIR/.config/gh/config.yml"
    "apps/claude/mcp-servers.json:$HOME_DIR/.config/claude/mcp-servers.json"
    
    # Phase 3: エディター設定（任意）
    "editors/zed/settings.json:$HOME_DIR/.config/zed/settings.json"
    "editors/vscode/settings.json:$HOME_DIR/Library/Application Support/Code/User/settings.json"
    "editors/nvim:$HOME_DIR/.config/nvim"
    
    # Phase 4: ウィンドウマネージャー設定（macOS限定・任意）
    "wm/yabai/yabairc:$HOME_DIR/.config/yabai/yabairc"
    "wm/skhd/skhdrc:$HOME_DIR/.config/skhd/skhdrc"
    "wm/sketchybar/sketchybarrc:$HOME_DIR/.config/sketchybar/sketchybarrc"
    
    # Note: Sensitive files (.gitconfig, ssh/config, claude.json) are excluded for security
    # See .example files in respective directories for templates
)

# バックアップ一覧を表示
list_backups() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_info "バックアップディレクトリが存在しません: $BACKUP_DIR"
        return
    fi
    
    log_info "既存のバックアップ一覧:"
    echo
    
    local backup_count=0
    for backup_dir in "$BACKUP_DIR"/backup_*; do
        if [[ -d "$backup_dir" ]]; then
            local dir_name
            dir_name=$(basename "$backup_dir")
            local timestamp="${dir_name#backup_}"
            local date_part="${timestamp:0:8}"
            local time_part="${timestamp:9:6}"
            local formatted_date="${date_part:0:4}-${date_part:4:2}-${date_part:6:2}"
            local formatted_time="${time_part:0:2}:${time_part:2:2}:${time_part:4:2}"
            local file_count
            file_count=$(find "$backup_dir" -type f | wc -l | tr -d ' ')
            
            echo "  📁 $dir_name"
            echo "     📅 $formatted_date $formatted_time"
            echo "     📄 $file_count ファイル"
            echo
            backup_count=$((backup_count + 1))
        fi
    done
    
    if [[ $backup_count -eq 0 ]]; then
        log_info "バックアップは見つかりませんでした"
    else
        log_info "合計 $backup_count 個のバックアップが見つかりました"
    fi
}

# 古いバックアップを削除
cleanup_old_backups() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_info "バックアップディレクトリが存在しません: $BACKUP_DIR"
        return
    fi
    
    log_info "バックアップディレクトリをクリーンアップしています..."
    
    # .DS_Storeファイルを削除
    find "$BACKUP_DIR" -name ".DS_Store" -delete 2>/dev/null || true
    
    local deleted_count=0
    local empty_deleted_count=0
    local seven_days_ago
    seven_days_ago=$(date -d '7 days ago' +%Y%m%d 2>/dev/null || date -v-7d +%Y%m%d)
    
    for backup_dir in "$BACKUP_DIR"/backup_*; do
        if [[ -d "$backup_dir" ]]; then
            local dir_name
            dir_name=$(basename "$backup_dir")
            local timestamp="${dir_name#backup_}"
            local date_part="${timestamp:0:8}"
            
            # 空のディレクトリをチェック
            local file_count
            file_count=$(find "$backup_dir" -type f | wc -l | tr -d ' ')
            
            if [[ "$file_count" -eq 0 ]]; then
                rm -rf "$backup_dir"
                log_info "空のバックアップを削除: $dir_name"
                empty_deleted_count=$((empty_deleted_count + 1))
            elif [[ "$date_part" < "$seven_days_ago" ]]; then
                rm -rf "$backup_dir"
                log_info "古いバックアップを削除: $dir_name (7日以上前)"
                deleted_count=$((deleted_count + 1))
            fi
        fi
    done
    
    # 削除結果の表示
    local total_deleted=$((deleted_count + empty_deleted_count))
    if [[ $total_deleted -eq 0 ]]; then
        log_info "削除対象のバックアップはありませんでした"
    else
        local message="バックアップクリーンアップ完了: "
        [[ $deleted_count -gt 0 ]] && message+="古いバックアップ${deleted_count}個 "
        [[ $empty_deleted_count -gt 0 ]] && message+="空のバックアップ${empty_deleted_count}個 "
        message+="を削除しました"
        log_success "$message"
    fi
}

# シンボリックリンクの状態をチェック
check_symlink_status() {
    local target_path="$1"
    local expected_source="$2"
    
    debug "Checking symlink status: $target_path -> $expected_source"
    
    if [[ -L "$target_path" ]]; then
        local current_target
        current_target=$(readlink "$target_path")
        debug "Found symlink: $target_path -> $current_target"
        if [[ "$current_target" == "$expected_source" ]]; then
            debug "Symlink is correct"
            echo "correct"
        else
            debug "Symlink is incorrect (expected: $expected_source, found: $current_target)"
            echo "incorrect"
        fi
    elif [[ -e "$target_path" ]]; then
        debug "File exists but is not a symlink: $target_path"
        echo "file_exists"
    else
        debug "Target path does not exist: $target_path"
        echo "missing"
    fi
}

# バックアップディレクトリの作成（条件付き）
create_backup_dir() {
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_session_dir="$BACKUP_DIR/backup_$timestamp"
    
    if [[ ! -d "$backup_session_dir" ]]; then
        mkdir -p "$backup_session_dir" >/dev/null 2>&1
        log_info "バックアップディレクトリを作成しました: $backup_session_dir" >&2
    fi
    
    echo "$backup_session_dir"
}

# 既存ファイルのバックアップ（条件付き）
backup_existing_files() {
    local backup_session_dir="$1"
    local backup_needed=false
    
    for dotfile_entry in "${DOTFILES_LIST[@]}"; do
        local source_path="${dotfile_entry%%:*}"
        local target_path="${dotfile_entry##*:}"
        local full_source_path="$CONFIG_DIR/$source_path"
        
        # ソースファイルが存在しない場合はスキップ
        if [[ ! -f "$full_source_path" ]]; then
            continue
        fi
        
        local status
        status=$(check_symlink_status "$target_path" "$full_source_path")
        
        # 正しいシンボリックリンクが既に存在し、強制モードでない場合はスキップ
        if [[ "$status" == "correct" ]] && [[ "$FORCE_MODE" != "true" ]]; then
            continue
        fi
        
        # バックアップが必要な場合のみ処理
        if [[ "$status" == "file_exists" ]] || [[ "$status" == "incorrect" ]]; then
            if [[ "$backup_needed" == "false" ]]; then
                log_info "バックアップが必要なファイルが見つかりました..."
                backup_needed=true
            fi
            
            local backup_path
            backup_path="$backup_session_dir/$(basename "$target_path")"
            
            if [[ -L "$target_path" ]]; then
                log_warning "$(basename "$target_path") は不正なシンボリックリンクです"
                readlink "$target_path" > "$backup_path.symlink_target"
                rm "$target_path"
            else
                mv "$target_path" "$backup_path"
                log_info "$(basename "$target_path") をバックアップしました"
            fi
        fi
    done
    
    echo "$backup_needed"
}

# シンボリックリンクの作成（冪等性対応）
create_symlinks() {
    local changes_made=false
    
    debug "Starting symlink creation process"
    
    for dotfile_entry in "${DOTFILES_LIST[@]}"; do
        local source_path="${dotfile_entry%%:*}"
        local target_path="${dotfile_entry##*:}"
        local full_source_path="$CONFIG_DIR/$source_path"
        
        debug "Processing: $source_path -> $target_path"
        
        if [[ ! -f "$full_source_path" ]]; then
            log_warning "ソースファイルが見つかりません: $full_source_path"
            log_info "スキップします: $(basename "$target_path")"
            debug "Skipping due to missing source file"
            continue
        fi
        
        local status
        status=$(check_symlink_status "$target_path" "$full_source_path")
        debug "Symlink status for $target_path: $status"
        
        # 既に正しいシンボリックリンクが存在し、強制モードでない場合はスキップ
        if [[ "$status" == "correct" ]] && [[ "$FORCE_MODE" != "true" ]]; then
            log_info "$(basename "$target_path") は既に正しく設定されています"
            debug "Skipping - already correctly configured"
            continue
        fi
        
        # 初回のメッセージ出力
        if [[ "$changes_made" == "false" ]]; then
            log_info "シンボリックリンクを作成しています..."
            changes_made=true
        fi
        
        # ターゲットディレクトリが存在しない場合は作成
        local target_dir
        target_dir=$(dirname "$target_path")
        if [[ ! -d "$target_dir" ]]; then
            debug "Creating target directory: $target_dir"
            mkdir -p "$target_dir"
        fi
        
        # シンボリックリンクを作成
        debug "Creating symlink: ln -sf $full_source_path $target_path"
        ln -sf "$full_source_path" "$target_path"
        log_success "$(basename "$target_path") のシンボリックリンクを作成しました"
    done
    
    if [[ "$changes_made" == "false" ]]; then
        log_info "すべてのシンボリックリンクは既に正しく設定されています"
        debug "No changes needed - all symlinks already correct"
    fi
}

# メイン処理
main() {
    # バックアップ一覧表示のみの場合
    if [[ "$SHOW_BACKUPS" == "true" ]]; then
        list_backups
        exit 0
    fi
    
    # バックアップ削除のみの場合
    if [[ "$CLEANUP_BACKUPS" == "true" ]]; then
        cleanup_old_backups
        exit 0
    fi
    
    log_info "ドットファイル管理システムのインストールを開始します"
    log_info "Dotfiles directory: $DOTFILES_DIR"
    
    if [[ "$FORCE_MODE" == "true" ]]; then
        log_info "強制モード: 既存の設定を上書きします"
    fi
    
    # 必要なディレクトリの存在確認
    if [[ ! -d "$CONFIG_DIR" ]]; then
        log_error "configs ディレクトリが見つかりません: $CONFIG_DIR"
        exit 1
    fi
    
    # バックアップの実行（条件付き）
    local backup_session_dir
    backup_session_dir=$(create_backup_dir)
    local backup_needed
    backup_needed=$(backup_existing_files "$backup_session_dir")
    
    # シンボリックリンクの作成
    create_symlinks
    
    log_success "ドットファイル管理システムのインストールが完了しました"
    
    # バックアップが実際に作成された場合のみメッセージを表示
    if [[ "$backup_needed" == "true" ]]; then
        log_info "バックアップは以下に保存されました: $backup_session_dir"
    fi
    
    # インストール後の確認
    echo
    log_info "作成されたシンボリックリンクの確認:"
    
    local total_links=0
    local working_links=0
    local missing_source_files=0
    
    for dotfile_entry in "${DOTFILES_LIST[@]}"; do
        local source_path="${dotfile_entry%%:*}"
        local target_path="${dotfile_entry##*:}"
        local full_source_path="$CONFIG_DIR/$source_path"
        local file_name
        file_name=$(basename "$target_path")
        
        total_links=$((total_links + 1))
        
        if [[ ! -f "$full_source_path" ]]; then
            echo "  ⚠️  $file_name (ソースファイルなし)"
            missing_source_files=$((missing_source_files + 1))
        elif [[ -L "$target_path" ]]; then
            local link_target
            link_target=$(readlink "$target_path")
            if [[ "$link_target" == "$full_source_path" ]]; then
                echo "  ✅ $file_name -> $(basename "$(dirname "$link_target")")/$(basename "$link_target")"
                working_links=$((working_links + 1))
            else
                echo "  ❌ $file_name -> $link_target (間違ったリンク)"
            fi
        else
            echo "  ❌ $file_name (リンクなし)"
        fi
    done
    
    echo
    log_info "概要: $working_links/$total_links ファイルが正常に設定されました"
    
    if [[ $missing_source_files -gt 0 ]]; then
        log_warning "$missing_source_files 個のソースファイルが見つかりませんでした"
    fi
    
    if [[ $working_links -eq 0 ]]; then
        log_warning "シンボリックリンクが作成されませんでした"
        log_info "configs/ ディレクトリの内容を確認してください"
    fi
}

# スクリプトが直接実行された場合のみmainを呼び出す
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi