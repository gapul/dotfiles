#!/bin/sh
# AeroSpace キーバインド使用ログ (nvim-in-the-loop と同じ「使うたびに記録」方式)
# 各 binding から `exec-and-forget <this> <label>` で detached 呼び出しされる。
# ネイティブの動作は binding 側で先に実行済みなので、ここが多少遅くても操作感に影響しない。
#
# 出力: ~/.local/share/aerospace/keybinds.jsonl (1操作1行の JSONL)
#   ts    … 発火時刻 (ローカル=JST, ISO8601)
#   label … 押されたキーコンビ (例: cmd-ctrl-alt-h)。config 側でキー名をそのまま渡す
#   ws    … その時フォーカスしていた workspace
#   app   … その時フォーカスしていたアプリ名
#
# 解析は貯まった JSONL を Claude Code に読ませて行う (AI/CLI 常駐は無し)。
set -eu

label="${1:-unknown}"
log_dir="$HOME/.local/share/aerospace"
log_file="$log_dir/keybinds.jsonl"
mkdir -p "$log_dir"

ts=$(date +%Y-%m-%dT%H:%M:%S%z)
# 文脈 (取得失敗しても記録は続ける)
ws=$(aerospace list-workspaces --focused 2>/dev/null || echo "")
app=$(aerospace list-windows --focused --format '%{app-name}' 2>/dev/null | head -1 || echo "")

# JSON 値のエスケープ (最低限: バックスラッシュとダブルクォート)
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

printf '{"ts":"%s","label":"%s","ws":"%s","app":"%s"}\n' \
  "$(esc "$ts")" "$(esc "$label")" "$(esc "$ws")" "$(esc "$app")" \
  >> "$log_file"
