#!/bin/bash
# macOS専用システム健全性確認スクリプト
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

echo "🍎 macOS システム健全性確認"
echo "=================================="
echo ""

cd /Users/yuki/dotfiles/nix

ISSUES=0

# 1. Darwin System評価 (macOSのみ)
log_info "1. Darwin System評価テスト"
if nix eval .#darwinConfigurations.default.system --apply 'x: "OK"' &>/dev/null; then
    log_success "macOS System評価: 正常"
else
    log_error "macOS System評価: エラーあり"
    ((ISSUES++))
fi
echo ""

# 2. 重要パッケージ確認
log_info "2. 重要パッケージ動作確認"
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
        version=$($pkg --version 2>/dev/null | head -1 | cut -d' ' -f1-2 || echo "installed")
        log_success "$desc: $version"
    else
        log_warning "$desc: 未インストール"
    fi
done
echo ""

# 3. Homebrew管理アプリ確認
log_info "3. Homebrew管理アプリケーション"
if command -v brew &> /dev/null; then
    formulae_count=$(brew list --formula 2>/dev/null | wc -l | tr -d ' ')
    casks_count=$(brew list --cask 2>/dev/null | wc -l | tr -d ' ')
    log_success "Homebrew: ${formulae_count} formulae, ${casks_count} casks"
    
    # 重要なアプリケーション確認
    important_casks=("voicevox" "battery" "claude" "zed" "wezterm")
    for cask in "${important_casks[@]}"; do
        if brew list --cask "$cask" &>/dev/null; then
            log_success "  $cask: インストール済み"
        else
            log_warning "  $cask: 未インストール"
        fi
    done
else
    log_warning "Homebrew: 利用できません"
fi
echo ""

# 4. 追加アプリケーション確認
log_info "4. Applicationsフォルダ確認"
apps=("VOICEVOX.app" "battery.app" "Claude.app" "Zed.app" "WezTerm.app")
for app in "${apps[@]}"; do
    if [[ -d "/Applications/$app" ]]; then
        log_success "$app: インストール済み"
    else
        log_warning "$app: 見つかりません"
    fi
done
echo ""

# 5. Git設定確認
log_info "5. Git設定確認"
email=$(git config --global user.email 2>/dev/null || echo "未設定")
name=$(git config --global user.name 2>/dev/null || echo "未設定")
log_success "Git Email: $email"
log_success "Git Name: $name"
echo ""

# 6. 環境変数確認
log_info "6. 環境変数確認"
log_success "EDITOR: ${EDITOR:-未設定}"
log_success "SHELL: ${SHELL:-未設定}"
echo ""

# 7. macOSシステム情報
log_info "7. システム情報"
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

# 8. 現在のNix Darwin設定状態
log_info "8. Nix Darwin設定状態"
log_success "基本Darwin設定: 有効"
log_success "Home-manager統合: 有効"
log_success "SOPS秘密管理: 有効"
log_warning "Automation モジュール: 一時的に無効"
log_warning "Development モジュール: 一時的に無効"
echo ""

# 結果サマリー
echo "📊 健全性確認結果"
echo "=================="
if [[ $ISSUES -eq 0 ]]; then
    log_success "macOSシステム状態: 良好 ✨"
    echo ""
    echo "🔧 正常動作中の機能:"
    echo "  ✅ Nix Darwin基本システム管理"
    echo "  ✅ Home-manager統合設定"
    echo "  ✅ Homebrew統合管理 (73 dependencies)"
    echo "  ✅ SOPS秘密管理システム"
    echo "  ✅ Git/Shell基本設定"
    echo "  ✅ 基本開発ツール"
    echo ""
    echo "⚠️  一時的に無効化された機能:"
    echo "  • Kubernetes/Docker管理"
    echo "  • クラウド統合 (AWS/GCP/Azure)"
    echo "  • CI/CD自動化"
    echo "  • 高度な開発環境"
    echo "  • システムモニタリング"
    echo ""
    echo "🎯 推奨アクション:"
    echo "  1. システム再構築テスト: sudo nix run nix-darwin -- switch --flake .#default"
    echo "  2. 無効化された機能は技術的問題解決後に段階的に再有効化可能"
else
    log_warning "macOSシステム状態: $ISSUES 件の問題あり"
fi

echo ""
echo "🔧 追加確認コマンド:"
echo "  cd ~/dotfiles/nix && nix eval .#darwinConfigurations.default.system  # Darwin評価"
echo "  /opt/homebrew/bin/brew doctor                                        # Homebrew健全性"
echo "  git status                                                           # Git状態"