#!/usr/bin/env bash
# 統合プロジェクト作成ツール
# Web、Python、Rust、Go、Docker等の開発環境テンプレート統合管理

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATES_DIR="$DOTFILES_ROOT/templates"

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

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

log_tech() {
    echo -e "${PURPLE}🚀 $1${NC}"
}

show_help() {
    cat << EOF
統合プロジェクト作成ツール - Dotfiles テンプレートシステム

USAGE:
    project-create.sh <project_name> [options]

OPTIONS:
    --type <type>            プロジェクトタイプ (web, python, rust, go, docker)
    --template <template>    具体的なテンプレート名
    --dir <directory>        作成先ディレクトリ (default: current)
    --interactive           インタラクティブモード
    --list                  利用可能テンプレート一覧
    -h, --help              このヘルプを表示

PROJECT TYPES:
    web                     Webアプリケーション
    python                  Python開発環境
    rust                    Rust開発環境  
    go                      Go開発環境
    docker                  Docker/コンテナ環境
    mobile                  モバイルアプリ開発

WEB TEMPLATES:
    react-vite              React + Vite (高速開発)
    nextjs                  Next.js (フルスタック)
    react-tauri             React + Tauri (デスクトップ)
    vue-vite                Vue + Vite

PYTHON TEMPLATES:
    fastapi                 FastAPI (Web API)
    django                  Django (Webアプリ)
    cli                     CLI Application
    data-science            データサイエンス
    ml                      機械学習

RUST TEMPLATES:
    cargo-cli               CLI Application
    web-server              Web Server (Axum)
    game                    Game Development

GO TEMPLATES:
    web-api                 REST API (Gin)
    cli                     CLI Application
    microservice            Microservice

EXAMPLES:
    project-create.sh my-app --type web --template react-vite
    project-create.sh api-server --type python --template fastapi
    project-create.sh cli-tool --type rust --template cargo-cli
    project-create.sh web-service --type go --template web-api
    project-create.sh --interactive
    project-create.sh --list

QUICK START:
    project-create.sh my-awesome-project
    cd my-awesome-project
    nix develop
    # Follow template-specific instructions
EOF
}

# テンプレート一覧表示
list_templates() {
    log_info "利用可能な開発環境テンプレート:"
    echo ""
    
    # Web templates
    echo -e "${CYAN}🌐 Web Development${NC}"
    if [[ -d "$TEMPLATES_DIR/web/frameworks" ]]; then
        find "$TEMPLATES_DIR/web/frameworks" -name "template-config.nix" | while read -r config; do
            local template_dir=$(dirname "$config")
            local template_name=$(basename "$template_dir")
            local display_name=$(grep 'displayName' "$config" 2>/dev/null | cut -d'"' -f2 || echo "$template_name")
            local description=$(grep 'description' "$config" 2>/dev/null | cut -d'"' -f2 || echo "No description")
            echo "  📦 $template_name - $display_name"
            echo "     $description"
        done
    fi
    echo ""
    
    # Python templates
    echo -e "${CYAN}🐍 Python Development${NC}"
    if [[ -d "$TEMPLATES_DIR/python" ]]; then
        find "$TEMPLATES_DIR/python" -name "template-config.nix" | while read -r config; do
            local template_dir=$(dirname "$config")
            local template_name=$(basename "$template_dir")
            local display_name=$(grep 'displayName' "$config" 2>/dev/null | cut -d'"' -f2 || echo "$template_name")
            local description=$(grep 'description' "$config" 2>/dev/null | cut -d'"' -f2 || echo "No description")
            echo "  📦 $template_name - $display_name"
            echo "     $description"
        done
    fi
    echo ""
    
    # Rust templates
    echo -e "${CYAN}🦀 Rust Development${NC}"
    if [[ -d "$TEMPLATES_DIR/rust" ]]; then
        find "$TEMPLATES_DIR/rust" -name "template-config.nix" | while read -r config; do
            local template_dir=$(dirname "$config")
            local template_name=$(basename "$template_dir")
            local display_name=$(grep 'displayName' "$config" 2>/dev/null | cut -d'"' -f2 || echo "$template_name")
            local description=$(grep 'description' "$config" 2>/dev/null | cut -d'"' -f2 || echo "No description")
            echo "  📦 $template_name - $display_name"
            echo "     $description"
        done
    fi
    echo ""
    
    # Go templates
    echo -e "${CYAN}🐹 Go Development${NC}"
    if [[ -d "$TEMPLATES_DIR/go" ]]; then
        find "$TEMPLATES_DIR/go" -name "template-config.nix" | while read -r config; do
            local template_dir=$(dirname "$config")
            local template_name=$(basename "$template_dir")
            local display_name=$(grep 'displayName' "$config" 2>/dev/null | cut -d'"' -f2 || echo "$template_name")
            local description=$(grep 'description' "$config" 2>/dev/null | cut -d'"' -f2 || echo "No description")
            echo "  📦 $template_name - $display_name"
            echo "     $description"
        done
    fi
}

# インタラクティブモード
interactive_mode() {
    log_info "🚀 統合プロジェクト作成 - インタラクティブモード"
    echo ""
    
    # プロジェクト名入力
    read -p "📁 プロジェクト名を入力してください: " project_name
    if [[ -z "$project_name" ]]; then
        log_error "プロジェクト名が必要です"
        exit 1
    fi
    
    # プロジェクトタイプ選択
    echo ""
    echo "🎯 プロジェクトタイプを選択してください:"
    echo "  1. Web Development (React, Vue, Next.js)"
    echo "  2. Python Development (FastAPI, Django, ML)"
    echo "  3. Rust Development (CLI, Web Server)"
    echo "  4. Go Development (API, CLI, Microservice)"
    echo "  5. Docker/Container Development"
    echo ""
    
    read -p "選択 (1-5, default: 1): " type_choice
    
    local project_type=""
    case "${type_choice:-1}" in
        1) project_type="web" ;;
        2) project_type="python" ;;
        3) project_type="rust" ;;
        4) project_type="go" ;;
        5) project_type="docker" ;;
        *) project_type="web" ;;
    esac
    
    # テンプレート選択
    echo ""
    local template=""
    case "$project_type" in
        web)
            echo "🌐 Webテンプレートを選択してください:"
            echo "  1. react-vite     - React + Vite (推奨)"
            echo "  2. nextjs         - Next.js フルスタック"
            echo "  3. react-tauri    - React + Tauri デスクトップ"
            echo "  4. vue-vite       - Vue + Vite"
            read -p "選択 (1-4, default: 1): " template_choice
            case "${template_choice:-1}" in
                1) template="react-vite" ;;
                2) template="nextjs" ;;
                3) template="react-tauri" ;;
                4) template="vue-vite" ;;
                *) template="react-vite" ;;
            esac
            ;;
        python)
            echo "🐍 Pythonテンプレートを選択してください:"
            echo "  1. fastapi        - FastAPI Web API (推奨)"
            echo "  2. django         - Django Webアプリ"
            echo "  3. cli            - CLI Application"
            echo "  4. data-science   - データサイエンス"
            echo "  5. ml             - 機械学習"
            read -p "選択 (1-5, default: 1): " template_choice
            case "${template_choice:-1}" in
                1) template="fastapi" ;;
                2) template="django" ;;
                3) template="cli" ;;
                4) template="data-science" ;;
                5) template="ml" ;;
                *) template="fastapi" ;;
            esac
            ;;
        rust)
            echo "🦀 Rustテンプレートを選択してください:"
            echo "  1. cargo-cli      - CLI Application (推奨)"
            echo "  2. web-server     - Web Server (Axum)"
            echo "  3. game           - Game Development"
            read -p "選択 (1-3, default: 1): " template_choice
            case "${template_choice:-1}" in
                1) template="cargo-cli" ;;
                2) template="web-server" ;;
                3) template="game" ;;
                *) template="cargo-cli" ;;
            esac
            ;;
        go)
            echo "🐹 Goテンプレートを選択してください:"
            echo "  1. web-api        - REST API (Gin) (推奨)"
            echo "  2. cli            - CLI Application"
            echo "  3. microservice   - Microservice"
            read -p "選択 (1-3, default: 1): " template_choice
            case "${template_choice:-1}" in
                1) template="web-api" ;;
                2) template="cli" ;;
                3) template="microservice" ;;
                *) template="web-api" ;;
            esac
            ;;
    esac
    
    # ディレクトリ選択
    echo ""
    read -p "📂 作成先ディレクトリ (default: current): " target_dir
    target_dir="${target_dir:-.}"
    
    # 確認
    echo ""
    log_info "設定確認:"
    echo "  プロジェクト名: $project_name"
    echo "  プロジェクトタイプ: $project_type"
    echo "  テンプレート: $template"
    echo "  作成先: $target_dir"
    echo ""
    
    read -p "この設定で作成しますか? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        create_project "$project_name" "$project_type" "$template" "$target_dir"
    else
        echo "作成をキャンセルしました"
        exit 0
    fi
}

# プロジェクト作成
create_project() {
    local project_name="$1"
    local project_type="$2"
    local template="$3"
    local target_dir="$4"
    
    local project_path="$target_dir/$project_name"
    
    log_tech "プロジェクト作成開始: $project_name ($project_type/$template)"
    
    # 適切なテンプレートマネージャーを呼び出し
    case "$project_type" in
        web)
            if command -v "$DOTFILES_ROOT/scripts/web-create.sh" &> /dev/null; then
                "$DOTFILES_ROOT/scripts/web-create.sh" "$project_name" --framework "$template" --dir "$target_dir"
            else
                log_error "Web template manager not found"
                exit 1
            fi
            ;;
        python|rust|go)
            # 汎用テンプレート作成
            create_generic_project "$project_name" "$project_type" "$template" "$target_dir"
            ;;
        *)
            log_error "Unsupported project type: $project_type"
            exit 1
            ;;
    esac
}

# 汎用テンプレート作成
create_generic_project() {
    local project_name="$1"
    local project_type="$2"
    local template="$3"
    local target_dir="$4"
    
    local template_dir="$TEMPLATES_DIR/$project_type/$template"
    local project_path="$target_dir/$project_name"
    
    # テンプレート存在確認
    if [[ ! -d "$template_dir" ]]; then
        log_error "テンプレートが見つかりません: $project_type/$template"
        return 1
    fi
    
    # プロジェクトディレクトリ作成
    if [[ -e "$project_path" ]]; then
        log_error "プロジェクトディレクトリが既に存在します: $project_path"
        return 1
    fi
    
    mkdir -p "$project_path"
    
    log_info "テンプレートファイルをコピー中..."
    
    # テンプレートファイルをコピーして変数置換
    find "$template_dir" -type f ! -name "template-config.nix" | while read -r file; do
        local relative_path="${file#$template_dir/}"
        local target_file="$project_path/$relative_path"
        
        # ディレクトリ作成
        mkdir -p "$(dirname "$target_file")"
        
        # ファイルコピーと変数置換
        sed "s/{{PROJECT_NAME}}/$project_name/g" "$file" > "$target_file"
        
        # 実行権限を保持
        if [[ -x "$file" ]]; then
            chmod +x "$target_file"
        fi
    done
    
    log_success "プロジェクト作成完了: $project_path"
    
    # 次のステップ表示
    echo ""
    log_info "次のステップ:"
    echo "  1. cd $project_name"
    echo "  2. nix develop      # Nix開発環境に入る"
    
    case "$project_type" in
        python)
            echo "  3. source venv/bin/activate  # Python仮想環境"
            echo "  4. pip install -r requirements-dev.txt"
            echo "  5. uvicorn main:app --reload  # FastAPI開発サーバー"
            ;;
        rust)
            echo "  3. cargo run        # アプリケーション実行"
            echo "  4. cargo test       # テスト実行"
            echo "  5. cargo build --release  # リリースビルド"
            ;;
        go)
            echo "  3. go mod tidy      # 依存関係整理"
            echo "  4. air              # ライブリロード開発"
            echo "  5. go test ./...    # テスト実行"
            ;;
    esac
}

# メイン処理
main() {
    local project_name=""
    local project_type=""
    local template=""
    local target_dir="."
    local interactive=false
    
    # 引数解析
    while [[ $# -gt 0 ]]; do
        case $1 in
            --type)
                project_type="$2"
                shift 2
                ;;
            --template)
                template="$2"
                shift 2
                ;;
            --dir)
                target_dir="$2"
                shift 2
                ;;
            --interactive)
                interactive=true
                shift
                ;;
            --list)
                list_templates
                exit 0
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                log_error "不明なオプション: $1"
                show_help
                exit 1
                ;;
            *)
                if [[ -z "$project_name" ]]; then
                    project_name="$1"
                else
                    log_error "不明な引数: $1"
                    show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # インタラクティブモード
    if [[ "$interactive" == true ]]; then
        interactive_mode
        return
    fi
    
    # プロジェクト名が必要
    if [[ -z "$project_name" ]]; then
        log_error "プロジェクト名が必要です"
        echo ""
        show_help
        exit 1
    fi
    
    # デフォルト値設定
    if [[ -z "$project_type" ]]; then
        project_type="web"
        log_info "プロジェクトタイプが未指定のため web を使用します"
    fi
    
    if [[ -z "$template" ]]; then
        case "$project_type" in
            web) template="react-vite" ;;
            python) template="fastapi" ;;
            rust) template="cargo-cli" ;;
            go) template="web-api" ;;
            *) template="default" ;;
        esac
        log_info "テンプレートが未指定のため $template を使用します"
    fi
    
    # プロジェクト作成
    create_project "$project_name" "$project_type" "$template" "$target_dir"
}

# スクリプト実行
main "$@"