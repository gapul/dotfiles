#!/bin/bash
# nix-shortcuts.sh - Convenient nix management shortcuts

set -euo pipefail

# Alias shortcuts for common nix operations
alias nrs="sudo darwin-rebuild switch --flake ~/.config/nix-darwin"
alias nrb="sudo darwin-rebuild build --flake ~/.config/nix-darwin"
alias nrc="nix flake check ~/.config/nix-darwin"
alias nru="cd ~/.config/nix-darwin && nix flake update && cd -"

alias hms="home-manager switch --flake ~/.config/nix-darwin"
alias hmb="home-manager build --flake ~/.config/nix-darwin"
alias hmg="home-manager generations"

alias ngc="nix store gc"
alias nopt="nix store optimise"
alias ngen="darwin-rebuild --list-generations"

# Function shortcuts
nix-rebuild() {
    echo "🔧 nix-darwin 再構築中..."
    sudo darwin-rebuild switch --flake ~/.config/nix-darwin
    echo "✅ 完了"
}

nix-update() {
    echo "📦 flake inputs 更新中..."
    cd ~/.config/nix-darwin
    nix flake update
    echo "🔧 システム再構築中..."
    sudo darwin-rebuild switch --flake .
    echo "🏠 home-manager 更新中..."
    home-manager switch --flake .
    cd -
    echo "✅ 全更新完了"
}

nix-clean() {
    echo "🧹 nix store クリーンアップ開始..."
    nix store gc
    nix store optimise
    echo "✅ クリーンアップ完了"
}

nix-status() {
    echo "📊 nix システム状態:"
    echo "  nix バージョン: $(nix --version)"
    echo "  darwin 世代数: $(darwin-rebuild --list-generations | wc -l)"
    echo "  home 世代数: $(home-manager generations | wc -l)"
    echo "  store サイズ: $(du -sh /nix/store 2>/dev/null | cut -f1)"
}

nix-search() {
    if [[ $# -eq 0 ]]; then
        echo "使用方法: nix-search <パッケージ名>"
        return 1
    fi
    nix search nixpkgs "$1"
}

nix-shell-run() {
    if [[ $# -lt 2 ]]; then
        echo "使用方法: nix-shell-run <パッケージ> <コマンド>"
        return 1
    fi
    local package="$1"
    shift
    nix-shell -p "$package" --run "$*"
}

# Add to shell if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo "📦 nix shortcuts loaded"
    echo "利用可能なコマンド:"
    echo "  nrs  - darwin-rebuild switch"
    echo "  hms  - home-manager switch"
    echo "  ngc  - nix store gc"
    echo "  nopt - nix store optimise"
    echo ""
    echo "  nix-rebuild  - システム再構築"
    echo "  nix-update   - フル更新"
    echo "  nix-clean    - クリーンアップ"
    echo "  nix-status   - システム状態"
    echo "  nix-search   - パッケージ検索"
fi