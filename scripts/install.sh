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

# DEPRECATED: File deployment now managed via nix home-manager
# This list is kept for reference and migration verification only
# All dotfiles are now deployed declaratively via nix/home.nix home.file configuration

# Migration Notice: This script now serves as a Nix setup wrapper
# For file deployment, use: home-manager switch --flake ~/dotfiles/nix

DEPRECATED_DOTFILES_LIST=(
    # MIGRATED TO: nix/home.nix home.file section
    # Phase 1: ".zshrc".source = "${dotfilesDirectory}/configs/zsh/zshrc"
    # Phase 2: ".docker/config.json".source = "${dotfilesDirectory}/configs/development/docker/config.json"
    # Phase 3: ".config/nvim".source = "${dotfilesDirectory}/configs/editors/nvim"
    # Phase 4: ".config/yabai/yabairc".source = "${dotfilesDirectory}/configs/wm/yabai/yabairc"
    # ... (See nix/home.nix for complete list)
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

# DEPRECATED: Legacy symlink functions removed
# These functions are no longer needed as file deployment is handled by home-manager
# 
# Legacy functions removed:
# - check_symlink_status() 
# - create_backup_dir()
# - backup_existing_files()
# - create_symlinks()
#
# Migration: All dotfile deployment is now managed declaratively via:
# nix/home.nix home.file configuration

# Nix初回セットアップ用ラッパー関数
setup_nix_environment() {
    log_info "Nix環境のセットアップを開始します..."
    
    # Nix が利用可能かチェック
    if ! command -v nix >/dev/null 2>&1; then
        log_error "Nixが見つかりません。先にNixをインストールしてください:"
        log_info "  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install"
        exit 1
    fi
    
    # nix-darwin がセットアップされているかチェック
    if ! command -v darwin-rebuild >/dev/null 2>&1; then
        log_warning "nix-darwinが見つかりません。システム設定はスキップします"
        log_info "nix-darwinのセットアップは docs/nix/ を参照してください"
    else
        log_info "nix-darwinが利用可能です"
    fi
    
    # home-manager がセットアップされているかチェック
    if ! command -v home-manager >/dev/null 2>&1; then
        log_error "home-managerが見つかりません。先にhome-managerをセットアップしてください:"
        log_info "  nix run home-manager/release-24.05 -- init --switch"
        exit 1
    fi
    
    log_success "Nix環境のセットアップチェックが完了しました"
}

# メイン処理 - 新しいNix初回セットアップ用ラッパー
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
    
    log_info "=== ドットファイル管理システム v2.0 - Nix統合版 ==="
    log_warning "⚠️  MIGRATION NOTICE: このスクリプトの役割が変更されました"
    echo
    log_info "🔄 従来のシンボリックリンク管理は廃止されました"
    log_info "✨ 代わりに home-manager による宣言的設定管理を使用します"
    echo
    
    log_info "🏗️  推奨セットアップ手順:"
    echo "  1. Nix環境のセットアップ確認"
    echo "  2. home-manager による設定適用"
    echo "  3. システム設定の適用（nix-darwin）"
    echo
    
    # Nix環境のセットアップチェック
    setup_nix_environment
    
    echo
    log_info "📁 設定ファイルのデプロイを実行しますか？"
    read -p "Continue? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "セットアップをキャンセルしました"
        exit 0
    fi
    
    # home-manager による設定適用
    log_info "🏠 home-manager による設定適用を実行中..."
    if cd "$DOTFILES_DIR/nix" && home-manager switch --flake .; then
        log_success "✅ home-manager による設定適用が完了しました"
    else
        log_error "❌ home-manager の実行に失敗しました"
        log_info "手動で実行してください: cd $DOTFILES_DIR/nix && home-manager switch --flake ."
        exit 1
    fi
    
    echo
    log_success "🎉 ドットファイル管理システムのセットアップが完了しました！"
    echo
    log_info "📚 詳細なドキュメント:"
    log_info "  - nix/README.md: Nix設定の詳細"
    log_info "  - CLAUDE.md: 開発者向けガイド"
    echo
    log_info "🔧 よく使うコマンド:"
    log_info "  - home-manager switch --flake ~/dotfiles/nix  : 設定の再適用"
    log_info "  - darwin-rebuild switch --flake ~/dotfiles/nix : システム設定の適用"
    log_info "  - just rebuild : 上記をまとめて実行（justfileが利用可能な場合）"
}

# スクリプトが直接実行された場合のみmainを呼び出す
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi