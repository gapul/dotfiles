#!/usr/bin/env bash
# Bitwarden から age 秘密鍵を取得して Windows と WSL の両方に配置する。
# WSL 内 (bash) で実行する想定。Windows 側 dotfiles は /mnt/c 経由で見えるので片方で完結。
#
# 使い方:
#   1. Windows 側で bw login (対話)
#       bw login <email>
#       export BW_SESSION=$(bw unlock --raw)
#   2. WSL 側でこのスクリプト実行
#       /mnt/c/Users/<user>/dotfiles/scripts/fetch-age-key.sh
#   または item name を明示:
#       AGE_ITEM='dotfiles age key' ./fetch-age-key.sh
set -euo pipefail

# bw CLI の場所 (WSL から Windows 側 bw を呼ぶ)
if command -v bw &>/dev/null; then
    BW=bw
elif compgen -G "/mnt/c/Users/${USER}/AppData/Local/Microsoft/WinGet/Packages/Bitwarden.CLI_*/bw.exe" >/dev/null; then
    BW=$(ls /mnt/c/Users/${USER}/AppData/Local/Microsoft/WinGet/Packages/Bitwarden.CLI_*/bw.exe | head -1)
else
    echo "ERROR: bw CLI が見つかりません" >&2
    exit 1
fi

# Bitwarden item 名 (環境変数で上書き可)
ITEM="${AGE_ITEM:-age}"

# Vault unlock 確認
if ! "$BW" status 2>/dev/null | grep -q '"status":"unlocked"'; then
    echo "ERROR: Bitwarden が unlock されていません" >&2
    echo "先に以下を実行してください:" >&2
    echo "  bw login <email>" >&2
    echo "  export BW_SESSION=\$(bw unlock --raw)" >&2
    exit 1
fi

# item 検索
echo "→ Bitwarden item '$ITEM' を検索中..."
ITEMS_JSON=$("$BW" list items --search "$ITEM" --session "${BW_SESSION:-}")
COUNT=$(echo "$ITEMS_JSON" | jq 'length')

if [ "$COUNT" -eq 0 ]; then
    echo "ERROR: '$ITEM' に一致する item が見つかりません" >&2
    echo "AGE_ITEM='exact name' を指定するか、bw list items --search ... で確認:" >&2
    "$BW" list items --search age --session "${BW_SESSION:-}" | jq -r '.[] | .name'
    exit 1
elif [ "$COUNT" -gt 1 ]; then
    echo "WARN: $COUNT 件 match。最初の 1 件を使用:" >&2
    echo "$ITEMS_JSON" | jq -r '.[] | "  - " + .name + " (id=" + .id + ")"'
fi

# age key を取り出す (notes / password / fields[*] のどこかにあるはず)
ITEM_JSON=$(echo "$ITEMS_JSON" | jq '.[0]')
KEY=$(echo "$ITEM_JSON" | jq -r '.notes // empty')
if [ -z "$KEY" ] || ! echo "$KEY" | grep -q "AGE-SECRET-KEY"; then
    KEY=$(echo "$ITEM_JSON" | jq -r '.login.password // empty')
fi
if [ -z "$KEY" ] || ! echo "$KEY" | grep -q "AGE-SECRET-KEY"; then
    KEY=$(echo "$ITEM_JSON" | jq -r '.fields[]?.value // empty' | grep -m1 "AGE-SECRET-KEY" || true)
fi

if [ -z "$KEY" ] || ! echo "$KEY" | grep -q "AGE-SECRET-KEY"; then
    echo "ERROR: item 内に AGE-SECRET-KEY... の文字列が見つかりません" >&2
    echo "$ITEM_JSON" | jq '{name, notes_has_age: (.notes // "" | contains("AGE-SECRET-KEY")), pw_has_age: (.login.password // "" | contains("AGE-SECRET-KEY"))}'
    exit 1
fi

echo "✓ age 鍵を取得"

# 配置先
WSL_DST="$HOME/.config/sops/age/keys.txt"
WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n' || echo "$USER")
WIN_DST="/mnt/c/Users/${WIN_USER}/.config/sops/age/keys.txt"

write_key() {
    local dst="$1"
    mkdir -p "$(dirname "$dst")"
    printf '%s\n' "$KEY" > "$dst"
    chmod 600 "$dst" 2>/dev/null || true
    echo "  → $dst"
}

echo "→ 配置中..."
write_key "$WSL_DST"
write_key "$WIN_DST"

echo ""
echo "✓ 完了。次:"
echo "  WSL: cd ~/.dotfiles && nix run github:nix-community/home-manager -- switch --flake nix#\$USER"
echo "  Win: 既存 bootstrap で OK (再実行不要)"
