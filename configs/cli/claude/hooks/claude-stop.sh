#!/usr/bin/env bash
# Claude Code の Stop hook: 応答（ターン）完了時に通知する。
# stdin に session 情報の JSON が渡される。
set -euo pipefail

input="$(cat)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
name="$(basename "${cwd:-$PWD}")"

exec "$HOME/.local/bin/agent-notify" "✅ Claude Code" "タスク完了: ${name}"
