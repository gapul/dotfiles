#!/bin/bash

# Claude Code Notifications
# Claude Codeがユーザーからの指示を待っている時に通知を送信

set -euo pipefail

# 設定ファイルのパス
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/notification-config.json"

# デフォルト設定
DEFAULT_TITLE="Claude Code"
DEFAULT_MESSAGE="ユーザーからの指示をお待ちしています"
DEFAULT_SOUND="default"

# 設定読み込み
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # jqが利用可能な場合は設定ファイルから読み込み
        if command -v jq >/dev/null 2>&1; then
            TITLE=$(jq -r --arg default "$DEFAULT_TITLE" '.title // $default' "$CONFIG_FILE")
            MESSAGE=$(jq -r --arg default "$DEFAULT_MESSAGE" '.message // $default' "$CONFIG_FILE")
            SOUND=$(jq -r --arg default "$DEFAULT_SOUND" '.sound // $default' "$CONFIG_FILE")
            ENABLED=$(jq -r '.enabled // true' "$CONFIG_FILE")
        else
            # jqがない場合はデフォルト設定
            TITLE="$DEFAULT_TITLE"
            MESSAGE="$DEFAULT_MESSAGE"
            SOUND="$DEFAULT_SOUND"
            ENABLED=true
        fi
    else
        # 設定ファイルがない場合はデフォルト設定
        TITLE="$DEFAULT_TITLE"
        MESSAGE="$DEFAULT_MESSAGE"
        SOUND="$DEFAULT_SOUND"
        ENABLED=true
    fi
}

# macOS通知送信
send_macos_notification() {
    local title="$1"
    local message="$2"
    local sound="$3"
    
    # osascriptを使用してmacOS通知を送信
    osascript -e "display notification \"$message\" with title \"$title\" sound name \"$sound\""
}

# terminal-notifier使用（利用可能な場合）
send_terminal_notification() {
    local title="$1"
    local message="$2"
    
    if command -v terminal-notifier >/dev/null 2>&1; then
        terminal-notifier -title "$title" -message "$message" -sound default
        return 0
    else
        return 1
    fi
}

# 通知送信のメイン関数
send_notification() {
    local custom_title="${1:-}"
    local custom_message="${2:-}"
    
    load_config
    
    # 通知が無効の場合は何もしない
    if [[ "$ENABLED" != "true" ]]; then
        return 0
    fi
    
    # カスタムメッセージがある場合は使用
    local final_title="${custom_title:-$TITLE}"
    local final_message="${custom_message:-$MESSAGE}"
    
    # 通知方法を試行（terminal-notifier → osascript）
    if ! send_terminal_notification "$final_title" "$final_message"; then
        send_macos_notification "$final_title" "$final_message" "$SOUND"
    fi
}

# Claude Codeプロセス監視
monitor_claude_process() {
    local check_interval=5
    local last_activity_file="/tmp/claude-code-activity"
    
    while true; do
        # Claude Codeプロセスの確認
        if pgrep -f "claude-code" >/dev/null 2>&1; then
            # アクティビティファイルの更新時刻を確認
            if [[ -f "$last_activity_file" ]]; then
                local last_modified=$(stat -f %m "$last_activity_file" 2>/dev/null || echo 0)
                local current_time=$(date +%s)
                local idle_time=$((current_time - last_modified))
                
                # 30秒以上アクティビティがない場合に通知
                if [[ $idle_time -gt 30 ]]; then
                    send_notification "Claude Code" "指示待ち状態です（${idle_time}秒経過）"
                    # 次の通知まで60秒待機
                    sleep 60
                fi
            fi
        fi
        
        sleep "$check_interval"
    done
}

# 使用方法表示
usage() {
    cat << EOF
Usage: $0 [OPTIONS] [COMMAND]

Claude Code通知システム

COMMANDS:
  send [title] [message]  - 通知を送信
  monitor                 - プロセス監視開始
  config                  - 設定ファイル作成
  test                    - テスト通知送信

OPTIONS:
  -h, --help             - このヘルプを表示

EXAMPLES:
  $0 send "Claude Code" "お疲れ様です"
  $0 monitor
  $0 test
EOF
}

# 設定ファイル作成
create_config() {
    cat > "$CONFIG_FILE" << EOF
{
  "enabled": true,
  "title": "Claude Code",
  "message": "ユーザーからの指示をお待ちしています",
  "sound": "default",
  "monitor_interval": 5,
  "idle_threshold": 30,
  "notification_cooldown": 60
}
EOF
    echo "設定ファイルを作成しました: $CONFIG_FILE"
}

# テスト通知
test_notification() {
    send_notification "Claude Code テスト" "通知システムが正常に動作しています"
}

# メイン処理
main() {
    case "${1:-}" in
        "send")
            send_notification "${2:-}" "${3:-}"
            ;;
        "monitor")
            echo "Claude Codeプロセス監視を開始しています..."
            monitor_claude_process
            ;;
        "config")
            create_config
            ;;
        "test")
            test_notification
            ;;
        "-h"|"--help"|"help")
            usage
            ;;
        "")
            send_notification
            ;;
        *)
            echo "不明なコマンド: $1"
            usage
            exit 1
            ;;
    esac
}

# スクリプト実行
main "$@"