#!/bin/bash

# ドットファイル管理システム - 共通ユーティリティ関数
# 各スクリプトで共通して使用される関数を定義

set -e  # エラー時に停止
set -u  # 未定義変数使用時にエラー
set -o pipefail  # パイプの途中でエラーが発生した場合も検出

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

# デバッグ出力関数
debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${YELLOW}[DEBUG]${NC} $1" >&2
    fi
}

# ディレクトリパス取得関数
get_dotfiles_dir() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    dirname "$script_dir"
}

# バックアップディレクトリ作成関数
create_backup_dir() {
    local base_dir="$1"
    local backup_dir
    backup_dir="$base_dir/backups/backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    echo "$backup_dir"
}

# シンボリックリンク作成関数
create_symlink() {
    local source="$1"
    local target="$2"
    local force_mode="${3:-false}"
    
    debug "Creating symlink: $target -> $source"
    
    if [[ ! -f "$source" && ! -d "$source" ]]; then
        log_warning "ソースファイルが見つかりません: $source"
        return 1
    fi
    
    if [[ -e "$target" || -L "$target" ]]; then
        if [[ "$force_mode" == "true" ]]; then
            rm -rf "$target"
            debug "Removed existing file/link: $target"
        else
            log_warning "ファイルが既に存在します: $target (--force オプションで上書き可能)"
            return 1
        fi
    fi
    
    # シンボリックリンクを作成
    ln -sf "$source" "$target"
    
    if [[ -L "$target" ]]; then
        log_success "$(basename "$target") のシンボリックリンクを作成しました"
        return 0
    else
        log_error "シンボリックリンクの作成に失敗しました: $target"
        return 1
    fi
}

# 相対パス取得関数
get_relative_path() {
    local source="$1"
    local target="$2"
    
    # realpath がある場合は使用、なければ簡易実装
    if command -v realpath >/dev/null 2>&1; then
        realpath --relative-to="$(dirname "$target")" "$source"
    else
        # 簡易的な相対パス計算
        python3 -c "import os; print(os.path.relpath('$source', '$(dirname "$target")'))"
    fi
}

# 設定ファイル検証関数
validate_config() {
    local config_file="$1"
    
    case "$config_file" in
        *.toml)
            if command -v python3 >/dev/null 2>&1; then
                python3 -c "
import sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        print('TOML library not available, skipping validation')
        sys.exit(0)

try:
    with open('$config_file', 'rb') as f:
        tomllib.load(f)
    print('TOML syntax OK: $config_file')
except Exception as e:
    print(f'TOML syntax error in $config_file: {e}')
    sys.exit(1)
" 2>/dev/null || true
            fi
            ;;
        *.json)
            if command -v python3 >/dev/null 2>&1; then
                python3 -c "
import json
try:
    with open('$config_file', 'r') as f:
        json.load(f)
    print('JSON syntax OK: $config_file')
except Exception as e:
    print(f'JSON syntax error in $config_file: {e}')
" 2>/dev/null || true
            fi
            ;;
    esac
}

# ヘルプ表示関数
show_help() {
    local script_name="$1"
    
    case "$script_name" in
        "install")
            cat << EOF
ドットファイル管理システム - インストールスクリプト

使用方法:
    $0 [オプション]

オプション:
    --force     既存のファイルを強制的に上書きします
    --help      このヘルプメッセージを表示します

例:
    $0                # 標準インストール
    $0 --force        # 強制上書きインストール
EOF
            ;;
        "backup")
            cat << EOF
ドットファイル管理システム - バックアップスクリプト

使用方法:
    $0 [オプション]

オプション:
    --list-backups    既存のバックアップを一覧表示します
    --help           このヘルプメッセージを表示します

例:
    $0                # バックアップ作成
    $0 --list-backups # バックアップ一覧表示
EOF
            ;;
        *)
            echo "ヘルプ情報が利用できません: $script_name"
            ;;
    esac
}