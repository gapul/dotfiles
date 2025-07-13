{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.dotfiles.system.notification;

  # 統一通知システム
  notificationScript = pkgs.writeShellScript "dotfiles-notify" ''
    #!/usr/bin/env bash
    # Unified Notification System for Terminal and Desktop
    set -euo pipefail

    # 通知設定
    NOTIFICATION_ENABLED=''${DOTFILES_NOTIFICATIONS:-true}
    NOTIFICATION_THRESHOLD=''${DOTFILES_NOTIFICATION_THRESHOLD:-3}
    NOTIFICATION_SOUND=''${DOTFILES_NOTIFICATION_SOUND:-true}

    # ヘルプ表示
    show_help() {
      cat << EOF
    Dotfiles Unified Notification System

    Usage:
      notify [options] <command>
      notify [options] --message "text"

    Options:
      -m, --message TEXT    Send notification message
      -t, --title TITLE     Notification title
      -s, --sound          Enable sound (default: $NOTIFICATION_SOUND)
      -q, --quiet          Disable sound
      -f, --force          Force notification regardless of threshold
      -h, --help           Show this help

    Examples:
      notify sleep 5                           # Monitor command completion
      notify --message "Build completed"       # Direct message
      notify -t "Deploy" -m "Success!"         # Title + message
      notify --quiet make build                # Silent notification

    Environment Variables:
      DOTFILES_NOTIFICATIONS=true             # Enable/disable notifications
      DOTFILES_NOTIFICATION_THRESHOLD=3       # Minimum seconds for command notifications
      DOTFILES_NOTIFICATION_SOUND=true        # Enable sound by default
    EOF
    }

    # 通知送信関数
    send_notification() {
      local title="$1"
      local message="$2"
      local enable_sound="$3"

      # 通知が無効な場合は何もしない
      if [[ "$NOTIFICATION_ENABLED" != "true" ]]; then
        return 0
      fi

      # WezTerm用通知
      if [[ -n "''${WEZTERM_EXECUTABLE:-}" ]]; then
        # ベル音
        if [[ "$enable_sound" == "true" ]]; then
          printf '\a'
        fi
        
        # カスタムメッセージ
        printf '\e]9;%s\e\\' "$title: $message"
        
        # ターミナルのタイトルバーにも表示
        printf '\e]0;%s - %s\e\\' "$title" "$message"
      fi

      # macOS用通知 (terminal-notifierがある場合)
      if command -v terminal-notifier &>/dev/null; then
        local args=()
        args+=(-title "$title")
        args+=(-message "$message")
        
        if [[ "$enable_sound" == "true" ]]; then
          args+=(-sound "Glass")
        fi
        
        terminal-notifier "''${args[@]}" &>/dev/null &
      fi

      # 標準的なnotify-send (Linux)
      if command -v notify-send &>/dev/null; then
        notify-send "$title" "$message" &>/dev/null &
      fi

      # システムログにも記録
      echo "$(date '+%Y-%m-%d %H:%M:%S') [NOTIFY] $title: $message" >> ~/.dotfiles-notifications.log
    }

    # コマンド実行と監視
    monitor_command() {
      local cmd=("$@")
      local start_time=$SECONDS
      local exit_code=0

      # コマンド実行
      "''${cmd[@]}" || exit_code=$?
      
      local end_time=$SECONDS
      local duration=$((end_time - start_time))

      # 閾値チェック
      if [[ $duration -ge $NOTIFICATION_THRESHOLD ]] || [[ "$FORCE_NOTIFICATION" == "true" ]]; then
        local command_name="''${cmd[0]}"
        local title="Command Completed"
        local message
        
        if [[ $exit_code -eq 0 ]]; then
          message="✅ '$command_name' completed successfully in ''${duration}s"
        else
          message="❌ '$command_name' failed (exit $exit_code) after ''${duration}s"
        fi

        send_notification "$title" "$message" "$ENABLE_SOUND"
      fi

      return $exit_code
    }

    # 引数解析
    TITLE="Dotfiles"
    MESSAGE=""
    ENABLE_SOUND="$NOTIFICATION_SOUND"
    FORCE_NOTIFICATION="false"
    DIRECT_MESSAGE="false"

    while [[ $# -gt 0 ]]; do
      case "$1" in
        -m|--message)
          MESSAGE="$2"
          DIRECT_MESSAGE="true"
          shift 2
          ;;
        -t|--title)
          TITLE="$2"
          shift 2
          ;;
        -s|--sound)
          ENABLE_SOUND="true"
          shift
          ;;
        -q|--quiet)
          ENABLE_SOUND="false"
          shift
          ;;
        -f|--force)
          FORCE_NOTIFICATION="true"
          shift
          ;;
        -h|--help)
          show_help
          exit 0
          ;;
        --)
          shift
          break
          ;;
        -*)
          echo "Unknown option: $1" >&2
          show_help
          exit 1
          ;;
        *)
          break
          ;;
      esac
    done

    # 実行モード判定
    if [[ "$DIRECT_MESSAGE" == "true" ]]; then
      # 直接メッセージ送信
      if [[ -z "$MESSAGE" ]]; then
        echo "Error: Message is required with --message option" >&2
        exit 1
      fi
      send_notification "$TITLE" "$MESSAGE" "$ENABLE_SOUND"
    elif [[ $# -gt 0 ]]; then
      # コマンド監視モード
      monitor_command "$@"
    else
      echo "Error: No command or message specified" >&2
      show_help
      exit 1
    fi
  '';

  # WezTerm通知テストスクリプト
  notificationTestScript = pkgs.writeShellScript "test-notifications" ''
    #!/usr/bin/env bash
    # Notification System Test Suite
    set -euo pipefail

    echo "🔔 Testing Dotfiles Notification System..."
    echo "========================================"
    echo ""

    # Test 1: 基本ベル通知
    echo "Test 1: Basic bell notification"
    printf '\a'
    echo "   ✅ Bell sent (should show toast notification)"
    sleep 2

    # Test 2: カスタム通知メッセージ  
    echo "Test 2: Custom notification message"
    printf '\e]9;%s\e\\' "Custom test notification message"
    echo "   ✅ Custom message sent"
    sleep 2

    # Test 3: dotfiles-notify直接呼び出し
    echo "Test 3: Direct notify command"
    ${notificationScript} --message "Direct notification test" --title "Test"
    echo "   ✅ Direct notify command executed"
    sleep 2

    # Test 4: コマンド完了シミュレーション
    echo "Test 4: Command completion simulation"
    ${notificationScript} --force sleep 2
    echo "   ✅ Command completion notification sent"
    sleep 2

    # Test 5: WezTerm CLI (利用可能な場合)
    echo "Test 5: WezTerm CLI notification"
    if command -v wezterm &> /dev/null; then
        wezterm cli send-text --no-paste $'\a'
        echo "   ✅ WezTerm CLI command sent"
    else
        echo "   ⚠️  WezTerm CLI not available"
    fi

    # Test 6: terminal-notifier (macOS)
    echo "Test 6: macOS terminal-notifier"
    if command -v terminal-notifier &> /dev/null; then
        terminal-notifier -title "Dotfiles Test" -message "macOS notification test" -sound "Glass"
        echo "   ✅ macOS notification sent"
    else
        echo "   ⚠️  terminal-notifier not available"
    fi

    echo ""
    echo "🎉 Notification tests completed!"
    echo "If notifications didn't appear, check:"
    echo "  1. Terminal is WezTerm (for terminal notifications)"
    echo "  2. macOS notifications are enabled for terminal apps"
    echo "  3. Terminal-notifier is installed (brew install terminal-notifier)"
    echo "  4. Environment variables: DOTFILES_NOTIFICATIONS=true"
  '';

in {
  options.dotfiles.system.notification = {
    enable = mkEnableOption "Unified Notification System";

    defaultThreshold = mkOption {
      type = types.int;
      default = 3;
      description = "Default minimum seconds for command completion notifications";
    };

    enableSound = mkOption {
      type = types.bool;
      default = true;
      description = "Enable sound notifications by default";
    };

    enableTerminalNotifier = mkOption {
      type = types.bool;
      default = true;
      description = "Enable terminal-notifier for macOS desktop notifications";
    };

    logNotifications = mkOption {
      type = types.bool;
      default = true;
      description = "Log notifications to ~/.dotfiles-notifications.log";
    };
  };

  config = mkIf cfg.enable {
    # 通知システムパッケージ
    environment.systemPackages = with pkgs; [
      notificationScript
      notificationTestScript
    ] ++ optionals (cfg.enableTerminalNotifier && pkgs.stdenv.isDarwin) [
      terminal-notifier
    ];

    # 環境変数設定
    environment.variables = {
      DOTFILES_NOTIFICATIONS = "true";
      DOTFILES_NOTIFICATION_THRESHOLD = toString cfg.defaultThreshold;
      DOTFILES_NOTIFICATION_SOUND = if cfg.enableSound then "true" else "false";
    };

    # シェルエイリアスとヘルパー関数
    programs.zsh = mkIf cfg.enable {
      shellAliases = {
        "notify" = "dotfiles-notify";
        "test-notifications" = "test-notifications";
      };

      # Zsh統合用のヘルパー関数
      initContent = ''
        # Dotfiles通知システム統合
        notify_cmd() {
          if [[ $# -eq 0 ]]; then
            echo "Usage: notify_cmd <command>"
            return 1
          fi
          dotfiles-notify "$@"
        }

        # 長時間実行コマンドの自動通知
        autonotify_preexec() {
          if [[ -n "''${DOTFILES_AUTONOTIFY:-}" ]]; then
            export DOTFILES_CMD_START_TIME=$SECONDS
            export DOTFILES_CMD_LINE="$1"
          fi
        }

        autonotify_precmd() {
          if [[ -n "''${DOTFILES_AUTONOTIFY:-}" ]] && [[ -n "''${DOTFILES_CMD_START_TIME:-}" ]]; then
            local duration=$((SECONDS - DOTFILES_CMD_START_TIME))
            if [[ $duration -ge ''${DOTFILES_NOTIFICATION_THRESHOLD:-3} ]]; then
              local cmd_name=$(echo "$DOTFILES_CMD_LINE" | cut -d' ' -f1)
              dotfiles-notify --message "Command '$cmd_name' completed in ''${duration}s" --title "Terminal"
            fi
            unset DOTFILES_CMD_START_TIME DOTFILES_CMD_LINE
          fi
        }

        # ZSHフック登録 (オプトイン)
        if [[ "''${DOTFILES_AUTONOTIFY:-}" == "true" ]]; then
          add-zsh-hook preexec autonotify_preexec
          add-zsh-hook precmd autonotify_precmd
        fi
      '';
    };

    programs.bash = mkIf cfg.enable {
      shellAliases = {
        "notify" = "dotfiles-notify";
        "test-notifications" = "test-notifications";
      };

      # Bash統合用の設定
      initExtra = ''
        # Dotfiles通知システム統合
        notify_cmd() {
          if [[ $# -eq 0 ]]; then
            echo "Usage: notify_cmd <command>"
            return 1
          fi
          dotfiles-notify "$@"
        }
      '';
    };
  };
}