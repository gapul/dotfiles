#!/usr/bin/env bash
# tmux から Zellij への移行支援スクリプト
# Author: dotfiles automation
# Version: 1.0.0

set -euo pipefail

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
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

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

show_help() {
    cat << EOF
tmux から Zellij 移行支援ツール

USAGE:
    session-migrate.sh <command> [options]

COMMANDS:
    compare             tmux vs Zellij 機能比較表示
    migrate-sessions    既存 tmux セッションを Zellij に移行
    backup-tmux         tmux 設定をバックアップ
    create-aliases      移行用エイリアス作成
    health-check        移行状況確認

EXAMPLES:
    session-migrate.sh compare
    session-migrate.sh migrate-sessions
    session-migrate.sh health-check

OPTIONS:
    -h, --help          このヘルプを表示
    --dry-run           実際の操作を行わずにプレビュー
EOF
}

# 機能比較表示
show_comparison() {
    log_info "tmux vs Zellij 機能比較"
    echo ""
    
    cat << 'EOF'
┌─────────────────────┬─────────────────────┬─────────────────────┐
│      機能           │       tmux          │      Zellij         │
├─────────────────────┼─────────────────────┼─────────────────────┤
│ セッション永続化     │        ✅           │        ✅           │
│ デタッチ・アタッチ   │        ✅           │        ✅           │
│ マルチペイン        │        ✅           │        ✅           │
│ 設定ファイル        │    ~/.tmux.conf     │  ~/.config/zellij/  │
│ 言語               │        C            │       Rust          │
│ メモリ使用量        │      ~2-5MB         │      ~1-3MB         │
│ 起動速度           │       普通          │       高速          │
│ UI の美しさ         │       基本          │      モダン         │
│ プラグインシステム   │       あり          │       強化          │
│ レイアウト管理      │       手動          │       自動          │
│ 学習コスト         │       高い          │       低い          │
└─────────────────────┴─────────────────────┴─────────────────────┘

🎯 移行のメリット:
• 🚀 高速起動とレスポンス
• 🎨 モダンで直感的なUI
• 📦 充実したプラグインエコシステム
• ⚙️  簡単な設定管理
• 🔄 自動レイアウト復元

🤔 移行の注意点:
• tmux特有のスクリプトの書き換えが必要
• 一部のtmux専用プラグインは利用不可
• 設定ファイル形式が異なる (Bash → KDL)
EOF
}

# セッション移行
migrate_sessions() {
    log_info "tmux セッションの Zellij 移行を開始"
    
    # tmux セッション確認
    if ! command -v tmux &> /dev/null; then
        log_warning "tmux がインストールされていません"
        return 0
    fi
    
    # アクティブなtmuxセッション取得
    local tmux_sessions
    tmux_sessions=$(tmux list-sessions 2>/dev/null | cut -d: -f1 || echo "")
    
    if [[ -z "$tmux_sessions" ]]; then
        log_info "アクティブな tmux セッションがありません"
        return 0
    fi
    
    log_info "発見された tmux セッション:"
    echo "$tmux_sessions" | sed 's/^/  - /'
    echo ""
    
    # Zellij 確認
    if ! command -v zellij &> /dev/null; then
        log_error "Zellij がインストールされていません"
        log_info "まず Nix 設定を適用してください: nix develop"
        return 1
    fi
    
    # 各セッションを移行
    while IFS= read -r session; do
        [[ -z "$session" ]] && continue
        
        log_info "移行中: $session"
        
        # tmux セッション情報取得
        local pane_count
        pane_count=$(tmux list-panes -t "$session" 2>/dev/null | wc -l || echo "1")
        
        # Zellij セッション作成
        if [[ "$pane_count" -gt 1 ]]; then
            log_info "  複数ペイン検出 ($pane_count) → web レイアウトで作成"
            zellij --session "${session}-migrated" --layout web --detached || true
        else
            log_info "  単一ペイン → dev レイアウトで作成"
            zellij --session "${session}-migrated" --layout dev --detached || true
        fi
        
        log_success "  移行完了: $session → ${session}-migrated"
    done <<< "$tmux_sessions"
    
    echo ""
    log_success "セッション移行が完了しました"
    log_info "確認: zellij list-sessions"
}

# tmux設定バックアップ
backup_tmux() {
    log_info "tmux 設定のバックアップを作成"
    
    local backup_dir="$HOME/.config/tmux-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    
    # 設定ファイルバックアップ
    if [[ -f "$HOME/.tmux.conf" ]]; then
        cp "$HOME/.tmux.conf" "$backup_dir/"
        log_success "バックアップ: ~/.tmux.conf"
    fi
    
    # プラグインディレクトリバックアップ
    if [[ -d "$HOME/.tmux" ]]; then
        cp -r "$HOME/.tmux" "$backup_dir/"
        log_success "バックアップ: ~/.tmux/"
    fi
    
    # セッション情報バックアップ
    if command -v tmux &> /dev/null; then
        tmux list-sessions > "$backup_dir/sessions.txt" 2>/dev/null || echo "No sessions" > "$backup_dir/sessions.txt"
        log_success "バックアップ: セッション情報"
    fi
    
    log_success "バックアップ完了: $backup_dir"
}

# 移行用エイリアス作成
create_aliases() {
    log_info "移行用エイリアスを作成"
    
    local alias_file="$HOME/.zellij-migration-aliases"
    
    cat > "$alias_file" << 'EOF'
# Zellij Migration Aliases
# tmux ユーザー向けの互換エイリアス

# セッション管理
alias tmux='echo "Use zellij instead! Try: z (attach main) or zellij --session <name>"; false'
alias tls='zellij list-sessions'
alias tat='zellij attach'
alias tns='zellij --session'
alias tks='zellij kill-session'

# よく使うtmuxコマンドのZellij版
alias tmux-new='zellij --session'
alias tmux-attach='zellij attach'
alias tmux-list='zellij list-sessions'
alias tmux-kill='zellij kill-session'

# レイアウト関連
alias tmux-dev='zellij --layout dev'
alias tmux-web='zellij --layout web'

# 便利なショートカット
alias dev-session='zellij --session $(basename $(pwd)) --layout dev'
alias web-session='zellij --session $(basename $(pwd)) --layout web'

# ヘルプ表示
alias tmux-help='echo "Zellij commands:
  z                 - Attach to main session
  zellij --session  - Create new session
  zellij attach     - Attach to session  
  zellij list       - List sessions
  zdev              - Development layout
  zweb              - Web development layout
  
For more: zellij --help"'
EOF
    
    log_success "エイリアスファイル作成: $alias_file"
    log_info "使用方法: source $alias_file"
    
    # .zshrc に追加を提案
    if [[ -f "$HOME/.zshrc" ]] && ! grep -q "zellij-migration-aliases" "$HOME/.zshrc"; then
        echo ""
        log_info "次のコマンドで .zshrc に追加できます:"
        echo "echo 'source $alias_file' >> ~/.zshrc"
    fi
}

# 移行状況確認
health_check() {
    log_info "tmux → Zellij 移行状況チェック"
    echo ""
    
    # tmux 状況
    echo "📊 tmux 状況:"
    if command -v tmux &> /dev/null; then
        echo "   ✅ tmux: インストール済み"
        local tmux_sessions
        tmux_sessions=$(tmux list-sessions 2>/dev/null | wc -l || echo "0")
        echo "   📋 アクティブセッション: $tmux_sessions"
        
        if [[ -f "$HOME/.tmux.conf" ]]; then
            echo "   ✅ 設定ファイル: あり"
        else
            echo "   ⚪ 設定ファイル: なし"
        fi
    else
        echo "   ❌ tmux: 未インストール"
    fi
    
    echo ""
    echo "🚀 Zellij 状況:"
    if command -v zellij &> /dev/null; then
        echo "   ✅ Zellij: インストール済み"
        echo "   📦 バージョン: $(zellij --version)"
        
        local zellij_sessions
        zellij_sessions=$(zellij list-sessions 2>/dev/null | wc -l || echo "0")
        echo "   📋 アクティブセッション: $zellij_sessions"
        
        if [[ -f "$HOME/.config/zellij/config.kdl" ]]; then
            echo "   ✅ 設定ファイル: あり"
        else
            echo "   ❌ 設定ファイル: なし"
        fi
    else
        echo "   ❌ Zellij: 未インストール"
        echo "   💡 インストール: nix develop で利用可能"
    fi
    
    echo ""
    echo "🔧 推奨アクション:"
    
    # tmux セッションがある場合
    if command -v tmux &> /dev/null && [[ $(tmux list-sessions 2>/dev/null | wc -l || echo "0") -gt 0 ]]; then
        echo "   1. session-migrate.sh migrate-sessions  # セッション移行"
        echo "   2. session-migrate.sh backup-tmux       # 設定バックアップ"
    fi
    
    # Zellij が利用可能な場合
    if command -v zellij &> /dev/null; then
        echo "   3. zellij-health                        # Zellij環境確認"
        echo "   4. session-migrate.sh create-aliases    # 移行用エイリアス"
    else
        echo "   1. nix develop                          # Zellij環境セットアップ"
    fi
    
    echo "   5. session-migrate.sh compare            # 機能比較確認"
}

# メイン処理
main() {
    case "${1:-}" in
        compare)
            show_comparison
            ;;
        migrate-sessions)
            migrate_sessions
            ;;
        backup-tmux)
            backup_tmux
            ;;
        create-aliases)
            create_aliases
            ;;
        health-check)
            health_check
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