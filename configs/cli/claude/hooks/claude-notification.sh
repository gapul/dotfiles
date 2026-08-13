#!/usr/bin/env bash
# Claude Code の Notification hook: 入力待ち・許可待ち時に通知する。
# stdin の JSON に .message（待機理由）が入る。
set -euo pipefail

input="$(cat)"
msg="$(printf '%s' "$input" | jq -r '.message // "入力を待っています"' 2>/dev/null || echo "入力を待っています")"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
name="$(basename "${cwd:-$PWD}")"

exec "$HOME/.local/bin/agent-notify" "⏳ Claude Code (${name})" "$msg"
