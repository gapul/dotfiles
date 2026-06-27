#!/usr/bin/env bash
# WSL の最終 setup を一発で完了させる。
# - Nix profile を現セッションに load
# - age 鍵を heredoc 形式で受け取って WSL + Windows 両方に 600 で配置 (既配置なら skip)
# - home-manager apply (初回 30-60 分)
# - default shell を zsh に切替
#
# 使い方:
#   bash ~/.dotfiles/scripts/wsl-finalize.sh
#   または引数で age 鍵を渡す:
#   AGE_KEY_TEXT=$(cat /tmp/age.txt) bash ~/.dotfiles/scripts/wsl-finalize.sh
set -euo pipefail

# ─── 1. Nix profile load ───
if ! command -v nix &>/dev/null; then
    if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
        # shellcheck disable=SC1091
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
        echo "✓ Nix profile load"
    else
        echo "ERROR: Nix が install されていません。先に install してください:" >&2
        echo "  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install linux --no-confirm" >&2
        exit 1
    fi
else
    echo "✓ Nix 既に PATH に在り ($(nix --version | head -1))"
fi

# ─── 2. age 鍵配置 (WSL + Windows 両方) ───
WSL_KEY="$HOME/.config/sops/age/keys.txt"
WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n' || echo "$USER")
WIN_KEY="/mnt/c/Users/${WIN_USER}/.config/sops/age/keys.txt"

place_key() {
    local content="$1"
    mkdir -p "$(dirname "$WSL_KEY")" "$(dirname "$WIN_KEY")"
    printf '%s\n' "$content" > "$WSL_KEY"
    chmod 600 "$WSL_KEY"
    cp "$WSL_KEY" "$WIN_KEY"
    echo "✓ age 鍵を配置:"
    echo "    $WSL_KEY (600)"
    echo "    $WIN_KEY"
}

if [ -f "$WSL_KEY" ] && grep -q '^AGE-SECRET-KEY' "$WSL_KEY" 2>/dev/null; then
    echo "✓ age 鍵 既配置: $WSL_KEY"
    # Windows 側に無ければ同期
    if [ ! -f "$WIN_KEY" ] || ! cmp -s "$WSL_KEY" "$WIN_KEY"; then
        mkdir -p "$(dirname "$WIN_KEY")"
        cp "$WSL_KEY" "$WIN_KEY"
        echo "✓ Windows 側にも同期: $WIN_KEY"
    fi
elif [ -n "${AGE_KEY_TEXT:-}" ]; then
    # 環境変数で渡された場合
    place_key "$AGE_KEY_TEXT"
else
    # 対話で paste
    echo ""
    echo "─────────────────────────────────────────────────"
    echo " age 鍵を貼り付けてください (Mac で `cat ~/.config/sops/age/keys.txt`)"
    echo " 入力終了は Ctrl+D"
    echo "─────────────────────────────────────────────────"
    KEY_INPUT=$(cat)
    if ! echo "$KEY_INPUT" | grep -q '^AGE-SECRET-KEY'; then
        echo "ERROR: AGE-SECRET-KEY... の文字列が含まれていません" >&2
        exit 1
    fi
    place_key "$KEY_INPUT"
fi

# ─── 3. home-manager apply ───
echo ""
echo "─────────────────────────────────────────────────"
echo " home-manager apply (初回 30-60 分。flake build + 全パッケージ download)"
echo "─────────────────────────────────────────────────"
cd "$HOME/.dotfiles"
nix run github:nix-community/home-manager -- switch --flake "nix#$USER"

# ─── 4. zsh に chsh ───
ZSH_BIN=$(command -v zsh || true)
if [ -n "$ZSH_BIN" ] && [ "$SHELL" != "$ZSH_BIN" ]; then
    echo ""
    echo "→ default shell を zsh に切替"
    sudo chsh -s "$ZSH_BIN" "$USER" || chsh -s "$ZSH_BIN"
    echo "✓ 次回ログインから zsh"
fi

# ─── 5. SSH agent forward 確認 ───
echo ""
echo "═══ Final check ═══"
echo "SSH agent:"
ssh-add -l 2>&1 || true
echo ""
echo "完了。新しい WSL シェルを開いて確認してください。"
