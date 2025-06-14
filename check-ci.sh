#!/bin/bash

# ドットファイル管理システム - CI状態チェックスクリプト
# 最新のGitHub Actions CIの実行結果をチェックします

set -e

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

# GitHub CLIの認証チェック
check_gh_auth() {
    if ! gh auth status &>/dev/null; then
        log_error "GitHub CLIが認証されていません"
        log_info "次のコマンドを実行してください: gh auth login"
        exit 1
    fi
}

# 最新のCI実行結果をチェック
check_latest_ci() {
    log_info "最新のCI実行結果をチェックしています..."
    
    # 最新の実行を取得
    local latest_run
    latest_run=$(gh run list --limit 1 --json status,conclusion,displayTitle,createdAt,databaseId --jq '.[0]')
    
    if [[ -z "$latest_run" || "$latest_run" == "null" ]]; then
        log_warning "CI実行履歴が見つかりません"
        return 1
    fi
    
    local status conclusion title created_at run_id
    status=$(echo "$latest_run" | jq -r '.status')
    conclusion=$(echo "$latest_run" | jq -r '.conclusion')
    title=$(echo "$latest_run" | jq -r '.displayTitle')
    created_at=$(echo "$latest_run" | jq -r '.createdAt')
    run_id=$(echo "$latest_run" | jq -r '.databaseId')
    
    # 日時の整形
    local formatted_time
    formatted_time=$(date -d "$created_at" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$created_at" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$created_at")
    
    echo
    log_info "最新のCI実行情報:"
    echo "  タイトル: $title"
    echo "  実行時刻: $formatted_time"
    echo "  実行ID: $run_id"
    echo "  状態: $status"
    
    # 結果に応じた処理
    case "$status" in
        "completed")
            case "$conclusion" in
                "success")
                    log_success "✅ CI実行が成功しました！"
                    return 0
                    ;;
                "failure")
                    log_error "❌ CI実行が失敗しました"
                    echo
                    log_info "失敗したジョブの詳細を確認しますか？ [y/N]"
                    if [[ "${AUTO_YES:-false}" == "true" ]]; then
                        echo "y (自動応答)"
                        show_failure_details="y"
                    else
                        read -r show_failure_details
                    fi
                    
                    if [[ "$show_failure_details" =~ ^[Yy]$ ]]; then
                        log_info "失敗したジョブのログを表示しています..."
                        gh run view "$run_id" --log-failed || log_warning "ログの取得に失敗しました"
                    fi
                    return 1
                    ;;
                "cancelled")
                    log_warning "⚠️  CI実行がキャンセルされました"
                    return 1
                    ;;
                *)
                    log_warning "⚠️  CI実行が予期しない状態で完了しました: $conclusion"
                    return 1
                    ;;
            esac
            ;;
        "in_progress"|"queued")
            log_info "🔄 CI実行中です..."
            if [[ "${WAIT_FOR_COMPLETION:-false}" == "true" ]]; then
                log_info "CI実行の完了を待機しています..."
                wait_for_completion "$run_id"
            else
                log_info "進行状況を確認するには: gh run watch $run_id"
            fi
            return 2
            ;;
        *)
            log_warning "⚠️  予期しないCI状態: $status"
            return 1
            ;;
    esac
}

# CI完了まで待機
wait_for_completion() {
    local run_id="$1"
    local max_wait_time=600  # 10分
    local wait_interval=30   # 30秒間隔
    local elapsed_time=0
    
    while [[ $elapsed_time -lt $max_wait_time ]]; do
        local current_status
        current_status=$(gh run view "$run_id" --json status --jq '.status')
        
        case "$current_status" in
            "completed")
                log_info "CI実行が完了しました"
                check_latest_ci
                return $?
                ;;
            "in_progress"|"queued")
                log_info "待機中... (${elapsed_time}/${max_wait_time}秒経過)"
                sleep $wait_interval
                ((elapsed_time += wait_interval))
                ;;
            *)
                log_warning "予期しない状態: $current_status"
                return 1
                ;;
        esac
    done
    
    log_warning "タイムアウト: CI実行の完了を${max_wait_time}秒間待機しましたが完了しませんでした"
    return 1
}

# 直近のCI履歴を表示
show_recent_history() {
    log_info "直近のCI実行履歴:"
    gh run list --limit 5 --json status,conclusion,displayTitle,createdAt \
        --jq '.[] | "  " + .createdAt + " | " + .status + " | " + (.conclusion // "N/A") + " | " + .displayTitle' \
        | while read -r line; do
            echo "$line"
        done
}

# メイン処理
main() {
    local show_history=false
    # local wait_for_completion=false  # used via environment variable
    # local auto_yes=false  # used via environment variable
    
    # コマンドライン引数の処理
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                echo "使用方法: $0 [オプション]"
                echo "オプション:"
                echo "  --history, -l      直近のCI履歴を表示"
                echo "  --wait, -w         CI実行完了まで待機"
                echo "  --yes, -y          対話的な質問に自動で'yes'と応答"
                echo "  --help, -h         このヘルプを表示"
                exit 0
                ;;
            --history|-l)
                show_history=true
                shift
                ;;
            --wait|-w)
                export WAIT_FOR_COMPLETION=true
                shift
                ;;
            --yes|-y)
                export AUTO_YES=true
                shift
                ;;
            *)
                log_error "不明なオプション: $1"
                exit 1
                ;;
        esac
    done
    
    log_info "GitHub Actions CI状態チェッカー"
    echo
    
    # GitHub CLI認証チェック
    check_gh_auth
    
    # 履歴表示
    if [[ "$show_history" == "true" ]]; then
        show_recent_history
        echo
    fi
    
    # 最新のCI状態チェック
    local exit_code
    check_latest_ci
    exit_code=$?
    
    case $exit_code in
        0)
            log_success "すべてのチェックが正常に完了しました！"
            ;;
        1)
            log_error "CI実行でエラーが発生しています"
            ;;
        2)
            log_info "CI実行中です"
            ;;
    esac
    
    exit $exit_code
}

# スクリプトが直接実行された場合のみmainを呼び出す
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi