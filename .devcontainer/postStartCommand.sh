#!/bin/bash
# GitHub Codespaces起動後実行スクリプト
set -euo pipefail

echo "🔄 GitHub Codespaces 起動後セットアップ"

# 色設定
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }

# 1. Nix environment source
log_info "Nix環境読み込み"
if [[ -f /etc/profile.d/nix.sh ]]; then
    source /etc/profile.d/nix.sh
    log_success "Nix環境読み込み完了"
fi

# 2. Git リポジトリ状態確認
log_info "Git リポジトリ状態確認"
cd /workspaces/dotfiles
git status --short
log_success "Git状態確認完了"

# 3. 開発環境状態表示
log_info "開発環境状態"
echo "📂 作業ディレクトリ: $(pwd)"
echo "🌿 Git ブランチ: $(git branch --show-current 2>/dev/null || echo 'unknown')"
echo "👤 Git ユーザー: $(git config user.name) <$(git config user.email)>"
echo "🔧 利用可能コマンド:"
echo "  • claude          - Claude Code起動"
echo "  • dotfiles-rebuild - Home Manager再構築"
echo "  • dotfiles-health  - ヘルスチェック"
echo "  • gh              - GitHub CLI"

log_success "🚀 Codespaces環境準備完了!"