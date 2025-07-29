#!/usr/bin/env bash
# Web開発テンプレート管理システム
# Author: dotfiles automation
# Version: 1.0.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATES_DIR="$DOTFILES_ROOT/templates/web"

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ログ関数
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# ヘルプ表示
show_help() {
    cat << EOF
Web Template Manager - Dotfiles テンプレートシステム

USAGE:
    template-manager.sh <command> [options]

COMMANDS:
    list                    利用可能なテンプレート一覧
    create <name> <template> プロジェクト作成
    info <template>         テンプレート詳細情報
    validate <template>     テンプレート検証
    update                  テンプレート更新
    health                  システム健全性チェック

TEMPLATES:
    react-vite             React + Vite (推奨)
    nextjs                 Next.js (準備中)
    react-tauri            React + Tauri Desktop (準備中)
    vue-vite               Vue + Vite (準備中)

EXAMPLES:
    template-manager.sh list
    template-manager.sh create my-app react-vite
    template-manager.sh info react-vite
    template-manager.sh health

OPTIONS:
    -h, --help             このヘルプを表示
    -v, --verbose          詳細出力
    --dry-run              実際の操作を行わずにプレビュー
EOF
}

# テンプレート一覧表示
list_templates() {
    log_info "利用可能なWebテンプレート:"
    echo ""
    
    if [[ -d "$TEMPLATES_DIR/frameworks" ]]; then
        for template_dir in "$TEMPLATES_DIR/frameworks"/*; do
            if [[ -d "$template_dir" ]]; then
                local template_name=$(basename "$template_dir")
                local config_file="$template_dir/template-config.nix"
                
                if [[ -f "$config_file" ]]; then
                    local display_name=$(grep 'displayName' "$config_file" | cut -d'"' -f2 || echo "$template_name")
                    local description=$(grep 'description' "$config_file" | cut -d'"' -f2 || echo "No description available")
                    
                    echo "📦 $template_name"
                    echo "   名前: $display_name"
                    echo "   説明: $description"
                    echo ""
                else
                    echo "📦 $template_name (設定ファイルなし)"
                    echo ""
                fi
            fi
        done
    else
        log_warning "テンプレートディレクトリが見つかりません: $TEMPLATES_DIR/frameworks"
    fi
}

# テンプレート情報表示
show_template_info() {
    local template_name="$1"
    local template_dir="$TEMPLATES_DIR/frameworks/$template_name"
    local config_file="$template_dir/template-config.nix"
    
    if [[ ! -d "$template_dir" ]]; then
        log_error "テンプレートが見つかりません: $template_name"
        return 1
    fi
    
    if [[ ! -f "$config_file" ]]; then
        log_error "テンプレート設定ファイルが見つかりません: $config_file"
        return 1
    fi
    
    log_info "テンプレート情報: $template_name"
    echo ""
    
    # 設定ファイルから情報を抽出
    local display_name=$(grep 'displayName' "$config_file" | cut -d'"' -f2 || echo "$template_name")
    local description=$(grep 'description' "$config_file" | cut -d'"' -f2 || echo "No description")
    local framework=$(grep 'framework' "$config_file" | cut -d'"' -f2 || echo "unknown")
    local bundler=$(grep 'bundler' "$config_file" | cut -d'"' -f2 || echo "unknown")
    
    echo "📋 基本情報:"
    echo "   名前: $display_name"
    echo "   説明: $description"
    echo "   フレームワーク: $framework"
    echo "   バンドラー: $bundler"
    echo ""
    
    echo "📁 含まれるファイル:"
    if [[ -d "$template_dir" ]]; then
        find "$template_dir" -type f ! -name "template-config.nix" | while read -r file; do
            local relative_path="${file#$template_dir/}"
            echo "   - $relative_path"
        done
    fi
    echo ""
}

# プロジェクト作成
create_project() {
    local project_name="$1"
    local template_name="$2"
    local target_dir="${3:-.}"
    
    local template_dir="$TEMPLATES_DIR/frameworks/$template_name"
    local config_file="$template_dir/template-config.nix"
    local project_path="$target_dir/$project_name"
    
    # 検証
    if [[ ! -d "$template_dir" ]]; then
        log_error "テンプレートが見つかりません: $template_name"
        return 1
    fi
    
    if [[ -e "$project_path" ]]; then
        log_error "プロジェクトディレクトリが既に存在します: $project_path"
        return 1
    fi
    
    log_info "プロジェクト作成中: $project_name ($template_name)"
    
    # プロジェクトディレクトリ作成
    mkdir -p "$project_path"
    
    # コアファイルをコピー
    log_info "コアファイルをコピー中..."
    if [[ -d "$TEMPLATES_DIR/core" ]]; then
        cp -r "$TEMPLATES_DIR/core"/* "$project_path/"
    fi
    
    # テンプレート固有ファイルをコピー
    log_info "テンプレートファイルをコピー中..."
    find "$template_dir" -type f ! -name "template-config.nix" ! -name "shell.nix" | while read -r file; do
        local relative_path="${file#$template_dir/}"
        local target_file="$project_path/$relative_path"
        
        # ディレクトリ作成
        mkdir -p "$(dirname "$target_file")"
        
        # ファイルコピーと変数置換
        sed "s/{{PROJECT_NAME}}/$project_name/g" "$file" > "$target_file"
    done
    
    # package.json マージ
    log_info "パッケージ設定を更新中..."
    merge_package_json "$project_path/package.json" "$config_file" "$project_name"
    
    # Nix設定ファイル作成
    log_info "Nix環境設定を作成中..."
    if [[ -f "$template_dir/shell.nix" ]]; then
        cp "$template_dir/shell.nix" "$project_path/"
    fi
    
    # .envファイル作成
    create_env_file "$project_path" "$template_name"
    
    log_success "プロジェクト作成完了: $project_path"
    echo ""
    echo "次のステップ:"
    echo "  1. cd $project_name"
    echo "  2. nix develop  # Nix環境に入る"
    echo "  3. npm install  # 依存関係インストール"
    echo "  4. npm run dev  # 開発サーバー起動"
}

# package.json マージ
merge_package_json() {
    local package_file="$1"
    local config_file="$2"
    local project_name="$3"
    
    # ファイル存在確認
    if [[ ! -f "$package_file" ]]; then
        log_error "package.json が見つかりません: $package_file"
        return 1
    fi
    
    # テンプレートからパッケージ情報を抽出してpackage.jsonを更新
    # 一時ファイルを使用してより安全に処理
    local temp_file=$(mktemp)
    
    # プロジェクト名と説明を更新
    sed "s/@templates\/web-core/$project_name/g; s/Core web development template/$project_name - Modern web application/g" "$package_file" > "$temp_file"
    
    # 元ファイルに書き戻し
    mv "$temp_file" "$package_file"
    
    log_info "package.json updated for $project_name"
}

# .env ファイル作成
create_env_file() {
    local project_path="$1"
    local template_name="$2"
    
    cat > "$project_path/.env.example" << EOF
# Environment variables for $template_name project
# Copy this file to .env and fill in your values

# Development
NODE_ENV=development
PORT=3000

# API
# API_URL=http://localhost:8000

# Feature flags
# FEATURE_XYZ=false
EOF
    
    # .env作成
    cp "$project_path/.env.example" "$project_path/.env"
}

# テンプレート検証
validate_template() {
    local template_name="$1"
    local template_dir="$TEMPLATES_DIR/frameworks/$template_name"
    local config_file="$template_dir/template-config.nix"
    
    log_info "テンプレート検証中: $template_name"
    
    local errors=0
    
    # ディレクトリ存在確認
    if [[ ! -d "$template_dir" ]]; then
        log_error "テンプレートディレクトリが存在しません: $template_dir"
        ((errors++))
    fi
    
    # 設定ファイル存在確認
    if [[ ! -f "$config_file" ]]; then
        log_error "template-config.nix が存在しません: $config_file"
        ((errors++))
    fi
    
    # 必須ファイル確認
    local required_files=("package.json" "tsconfig.json" ".gitignore")
    for file in "${required_files[@]}"; do
        if [[ ! -f "$TEMPLATES_DIR/core/$file" ]]; then
            log_error "必須コアファイルが存在しません: $file"
            ((errors++))
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        log_success "テンプレート検証完了: すべてのファイルが正常です"
    else
        log_error "テンプレート検証失敗: $errors 個のエラーが見つかりました"
        return 1
    fi
}

# システム健全性チェック
health_check() {
    log_info "Webテンプレートシステム健全性チェック"
    echo ""
    
    local errors=0
    
    # テンプレートディレクトリ
    if [[ -d "$TEMPLATES_DIR" ]]; then
        log_success "テンプレートディレクトリ: 存在"
    else
        log_error "テンプレートディレクトリ: 不存在 ($TEMPLATES_DIR)"
        ((errors++))
    fi
    
    # コアテンプレート
    if [[ -d "$TEMPLATES_DIR/core" ]]; then
        log_success "コアテンプレート: 存在"
    else
        log_error "コアテンプレート: 不存在"
        ((errors++))
    fi
    
    # 必須ツール確認
    local tools=("node" "npm" "git")
    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            log_success "$tool: $(command -v "$tool")"
        else
            log_error "$tool: 未インストール"
            ((errors++))
        fi
    done
    
    # テンプレート数
    local template_count=$(find "$TEMPLATES_DIR/frameworks" -maxdepth 1 -type d | wc -l)
    template_count=$((template_count - 1))  # frameworks ディレクトリ自体を除く
    log_info "利用可能テンプレート数: $template_count"
    
    echo ""
    if [[ $errors -eq 0 ]]; then
        log_success "システム健全性チェック: すべて正常"
    else
        log_error "システム健全性チェック: $errors 個の問題が見つかりました"
        return 1
    fi
}

# メイン処理
main() {
    case "${1:-}" in
        list)
            list_templates
            ;;
        create)
            if [[ $# -lt 3 ]]; then
                log_error "使用法: template-manager.sh create <project_name> <template_name> [target_dir]"
                exit 1
            fi
            create_project "$2" "$3" "${4:-.}"
            ;;
        info)
            if [[ $# -lt 2 ]]; then
                log_error "使用法: template-manager.sh info <template_name>"
                exit 1
            fi
            show_template_info "$2"
            ;;
        validate)
            if [[ $# -lt 2 ]]; then
                log_error "使用法: template-manager.sh validate <template_name>"
                exit 1
            fi
            validate_template "$2"
            ;;
        health)
            health_check
            ;;
        update)
            log_info "テンプレート更新機能は実装中です"
            ;;
        -h|--help|help)
            show_help
            ;;
        "")
            log_error "コマンドが指定されていません"
            show_help
            exit 1
            ;;
        *)
            log_error "不明なコマンド: $1"
            show_help
            exit 1
            ;;
    esac
}

# スクリプト実行
main "$@"