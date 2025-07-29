#!/usr/bin/env bash
# Web開発プロジェクト作成ツール
# template-manager.shのラッパーとして簡単なインターフェースを提供

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_MANAGER="$SCRIPT_DIR/template-manager.sh"

# カラー定義
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

show_help() {
    cat << EOF
Web Create - 高速Webプロジェクト作成ツール

USAGE:
    web-create <project_name> [options]

OPTIONS:
    --framework <name>     フレームワーク選択 (default: react-vite)
    --dir <directory>      作成先ディレクトリ (default: current)
    --interactive         インタラクティブモード
    --list               利用可能テンプレート一覧
    -h, --help           このヘルプを表示

FRAMEWORKS:
    react-vite           React + Vite (推奨)
    nextjs               Next.js (準備中)
    react-tauri          React + Tauri Desktop (準備中)
    vue-vite             Vue + Vite (準備中)

EXAMPLES:
    web-create my-app                          # React + Vite で作成
    web-create my-app --framework nextjs       # Next.js で作成
    web-create my-app --dir ~/projects         # 指定ディレクトリに作成
    web-create --interactive                   # インタラクティブモード
    web-create --list                          # テンプレート一覧

QUICK START:
    web-create my-awesome-app
    cd my-awesome-app
    nix develop
    npm install
    npm run dev
EOF
}

# インタラクティブモード
interactive_mode() {
    log_info "🚀 Web プロジェクト作成 - インタラクティブモード"
    echo ""
    
    # プロジェクト名入力
    read -p "📁 プロジェクト名を入力してください: " project_name
    if [[ -z "$project_name" ]]; then
        echo "プロジェクト名が必要です"
        exit 1
    fi
    
    # テンプレート選択
    echo ""
    echo "📦 利用可能なテンプレート:"
    echo "  1. react-vite     - React + Vite (推奨)"
    echo "  2. nextjs         - Next.js (準備中)"
    echo "  3. react-tauri    - React + Tauri Desktop (準備中)"
    echo "  4. vue-vite       - Vue + Vite (準備中)"
    echo ""
    
    read -p "テンプレートを選択してください (1-4, default: 1): " template_choice
    
    case "${template_choice:-1}" in
        1) framework="react-vite" ;;
        2) framework="nextjs" ;;
        3) framework="react-tauri" ;;
        4) framework="vue-vite" ;;
        *) framework="react-vite" ;;
    esac
    
    # ディレクトリ選択
    echo ""
    read -p "📂 作成先ディレクトリ (default: current): " target_dir
    target_dir="${target_dir:-.}"
    
    # 確認
    echo ""
    log_info "設定確認:"
    echo "  プロジェクト名: $project_name"
    echo "  テンプレート: $framework"
    echo "  作成先: $target_dir"
    echo ""
    
    read -p "この設定で作成しますか? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        create_project "$project_name" "$framework" "$target_dir"
    else
        echo "作成をキャンセルしました"
        exit 0
    fi
}

# プロジェクト作成
create_project() {
    local project_name="$1"
    local framework="$2"
    local target_dir="$3"
    
    log_info "プロジェクト作成開始..."
    
    # template-manager.sh を呼び出し
    if "$TEMPLATE_MANAGER" create "$project_name" "$framework" "$target_dir"; then
        echo ""
        log_success "🎉 プロジェクト作成完了!"
        echo ""
        echo "🚀 次のステップ:"
        echo "  cd $project_name"
        echo "  nix develop      # Nix開発環境に入る"
        echo "  npm install      # 依存関係をインストール"
        echo "  npm run dev      # 開発サーバーを起動"
        echo ""
        echo "📚 その他のコマンド:"
        echo "  npm run build    # プロダクションビルド"
        echo "  npm run lint     # コードリント"
        echo "  npm run test     # テスト実行"
    else
        echo ""
        log_warning "プロジェクト作成でエラーが発生しました"
        echo "詳細は上記のエラーメッセージを確認してください"
        exit 1
    fi
}

# メイン処理
main() {
    local project_name=""
    local framework="react-vite"
    local target_dir="."
    local interactive=false
    
    # 引数解析
    while [[ $# -gt 0 ]]; do
        case $1 in
            --framework)
                framework="$2"
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
                "$TEMPLATE_MANAGER" list
                exit 0
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                echo "不明なオプション: $1"
                show_help
                exit 1
                ;;
            *)
                if [[ -z "$project_name" ]]; then
                    project_name="$1"
                else
                    echo "不明な引数: $1"
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
        echo "プロジェクト名が必要です"
        echo ""
        show_help
        exit 1
    fi
    
    # プロジェクト作成
    create_project "$project_name" "$framework" "$target_dir"
}

# スクリプト実行
main "$@"