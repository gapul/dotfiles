#!/bin/bash
# システム健全性包括確認スクリプト
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

echo "🏥 システム健全性包括確認"
echo "=================================="
echo ""

# Dynamically detect script location and navigate to nix directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/nix"

ISSUES=0

# 1. Nix Flake構文チェック
log_info "1. Nix Flake構文チェック"
if nix flake check --impure 2>/dev/null; then
    log_success "Flake構文: 正常"
else
    log_error "Flake構文: エラーあり"
    echo "詳細:"
    nix flake check --impure 2>&1 | head -10
    ((ISSUES++))
fi
echo ""

# 2. Darwin System評価
log_info "2. Darwin System評価テスト"
if nix eval .#darwinConfigurations.default.system --apply 'x: "OK"' &>/dev/null; then
    log_success "System評価: 正常"
else
    log_error "System評価: エラーあり"
    ((ISSUES++))
fi
echo ""

# 3. 重要パッケージ確認
log_info "3. 重要パッケージ動作確認"

packages=(
    "starship:Starship prompt"
    "git:Git version control"
    "zsh:Zsh shell"
    "nvim:Neovim editor"
)

for pkg_desc in "${packages[@]}"; do
    pkg="${pkg_desc%%:*}"
    desc="${pkg_desc##*:}"
    
    if command -v "$pkg" &> /dev/null; then
        version=$($pkg --version 2>/dev/null | head -1 | cut -d' ' -f2 || echo "installed")
        log_success "$desc: $version"
    else
        log_warning "$desc: 未インストール"
    fi
done
echo ""

# 4. Homebrew管理アプリ確認
log_info "4. Homebrew管理アプリケーション"
if command -v brew &> /dev/null; then
    formulae_count=$(brew list --formula 2>/dev/null | wc -l | tr -d ' ')
    casks_count=$(brew list --cask 2>/dev/null | wc -l | tr -d ' ')
    log_success "Homebrew: ${formulae_count} formulae, ${casks_count} casks"
else
    log_warning "Homebrew: 利用できません"
fi
echo ""

# 5. 追加アプリケーション確認
log_info "5. 新規追加アプリケーション確認"
apps=("VOICEVOX.app" "battery.app")
for app in "${apps[@]}"; do
    if [[ -d "/Applications/$app" ]]; then
        log_success "$app: インストール済み"
    else
        log_warning "$app: 見つかりません"
    fi
done
echo ""

# 6. Git設定確認
log_info "6. Git設定確認"
email=$(git config --global user.email 2>/dev/null || echo "未設定")
name=$(git config --global user.name 2>/dev/null || echo "未設定")
log_success "Git Email: $email"
log_success "Git Name: $name"
echo ""

# 7. 環境変数確認
log_info "7. 環境変数確認"
env_vars=("EDITOR" "SHELL" "PATH")
for var in "${env_vars[@]}"; do
    value="${!var:-未設定}"
    if [[ "$var" == "PATH" ]]; then
        # PATHは最初の3つのディレクトリのみ表示
        value=$(echo "$value" | cut -d':' -f1-3)"..."
    fi
    log_success "$var: $value"
done
echo ""

# 8. システムリソース確認
log_info "8. システムリソース確認"
if command -v sw_vers &> /dev/null; then
    macos_version=$(sw_vers -productVersion)
    log_success "macOS: $macos_version"
fi

# Nixストアサイズ
if [[ -d "/nix/store" ]]; then
    store_size=$(du -sh /nix/store 2>/dev/null | cut -f1 || echo "不明")
    log_success "Nixストア: $store_size"
fi
echo ""

# 9. 一時的に無効化されたモジュール確認
log_info "9. モジュール状態確認"
if grep -q "# ./common/automation/default.nix" "$SCRIPT_DIR/nix/flake.nix"; then
    log_warning "Automation モジュール: 一時的に無効"
else
    log_success "Automation モジュール: 有効"
fi

if grep -q "# ./common/development/default.nix" "$SCRIPT_DIR/nix/flake.nix"; then
    log_warning "Development モジュール: 一時的に無効"
else
    log_success "Development モジュール: 有効"
fi
echo ""

# 結果サマリー
echo "📊 健全性確認結果"
echo "=================="
if [[ $ISSUES -eq 0 ]]; then
    log_success "システム状態: 良好 ✨"
    echo ""
    echo "🔧 利用可能な機能:"
    echo "  • 基本システム管理 (Nix Darwin)"
    echo "  • Home-manager設定"
    echo "  • Homebrew統合管理"
    echo "  • Git/Shell設定"
    echo "  • 基本開発ツール"
    echo ""
    echo "⚠️  一時的に無効化された機能:"
    echo "  • 高度なAutomation機能"
    echo "  • 拡張Development環境"
    echo "  • Kubernetes/Cloud統合"
    echo ""
    echo "これらの機能は技術的問題解決後に再有効化可能です。"
else
    log_warning "システム状態: $ISSUES 件の問題あり"
    echo ""
    echo "🔧 対処方法:"
    echo "  1. エラーメッセージを確認"
    echo "  2. 問題のあるモジュールを特定"
    echo "  3. 段階的な修正を実施"
fi

echo ""
echo "🆘 追加確認コマンド:"
echo "  nix flake check --impure              # 構文チェック"
echo "  sudo nix run nix-darwin -- switch     # システム再構築テスト"
echo "  brew list                             # Homebrew管理確認"
echo "  git status                            # Git状態確認"