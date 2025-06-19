#!/bin/bash
# 簡単システム確認スクリプト
echo "🔍 システム簡易確認"
echo "=================="
echo ""

echo "✅ System Status:"
echo "  • macOS: $(sw_vers -productVersion)"
echo "  • Nix Store: $(du -sh /nix/store 2>/dev/null | cut -f1)"
echo "  • Homebrew: $(/opt/homebrew/bin/brew list --formula | wc -l | tr -d ' ') formulae, $(/opt/homebrew/bin/brew list --cask | wc -l | tr -d ' ') casks"
echo ""

echo "✅ Important Apps:"
for app in "VOICEVOX.app" "battery.app" "Claude.app" "Zed.app"; do
    if [[ -d "/Applications/$app" ]]; then
        echo "  ✅ $app"
    else
        echo "  ❌ $app"
    fi
done
echo ""

echo "✅ Git Config:"
echo "  • Email: $(git config --global user.email)"
echo "  • Name: $(git config --global user.name)"
echo ""

echo "🎯 Next Actions:"
echo "  • Full health check: cd ~/dotfiles && ./macos-health-check.sh"
echo "  • System rebuild: cd ~/dotfiles/nix && sudo nix run nix-darwin -- switch --flake .#default"
echo "  • Homebrew check: /opt/homebrew/bin/brew doctor"