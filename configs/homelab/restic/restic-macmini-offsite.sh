#!/bin/bash
# macmini の ~/Developer を共有 google-drive restic repo へ日次オフサイト (launchd)。
# 巨大/再現可能物 (node_modules/モデル/.git/objects 等) は除外。79G→約4G。
# 共有 repo のため forget は --host スコープ + prune なし (prune は母艦の日次に委譲)。
# macmini は sops 非導入のため秘密は手動配置の生ファイルを参照する。
set -uo pipefail

export PATH="$HOME/.local/state/nix/profiles/profile/bin:/usr/bin:/bin"
export RCLONE_CONFIG="$HOME/.config/rclone/rclone.conf"
export RESTIC_REPOSITORY="rclone:google-drive:restic-backup"
export RESTIC_PASSWORD_FILE="$HOME/.config/restic/password"

LOG="$HOME/Library/Logs/restic-macmini-offsite.log"
NTFY_URL_FILE="$HOME/.config/ntfy/url"
NTFY_TOKEN_FILE="$HOME/.config/ntfy/token"
HOST=$(hostname -s)

notify() {
  if [ -r "$NTFY_URL_FILE" ] && [ -r "$NTFY_TOKEN_FILE" ]; then
    /usr/bin/curl -fsS --max-time 15 \
      -H "Authorization: Bearer $(cat "$NTFY_TOKEN_FILE")" \
      -H "Title: restic ($HOST)" -H "Priority: high" -H "Tags: warning" \
      -d "$1" "$(cat "$NTFY_URL_FILE")" >/dev/null 2>&1 || true
  fi
}

mkdir -p "$(dirname "$LOG")"
exec >>"$LOG" 2>&1
echo "==================== $(date '+%F %T') backup start ($HOST) ===================="

if ! rclone about google-drive: >/dev/null 2>&1; then
  echo "SKIP: google-drive リモート未到達 (トークン失効の可能性)"
  notify "restic($HOST) ⚠️ リモート未到達: google-drive 未認証の可能性。ログ: $LOG"
  exit 0
fi

if ! restic snapshots >/dev/null 2>&1; then
  echo "ERROR: repo にアクセスできない"
  notify "restic($HOST) ⚠️ repo アクセス不可。ログ: $LOG"
  exit 1
fi

# 配布物の重み: **/models だけでは GPT-SoVITS の pretrained_models を拾えず、.pth/.ckpt/.pt が
# 素通りして 4.35GiB を毎日 Google Drive へ運んでいた (2026-08-12 判明)。HuggingFace から
# 落とし直せるので対象外。残るのは projects/ の非git作業と、push 済みリポジトリの差分だけ。
restic backup --verbose=1 \
  --exclude-caches \
  --exclude "**/node_modules" \
  --exclude "**/.venv" \
  --exclude "**/.direnv" \
  --exclude "**/target" \
  --exclude "**/dist" \
  --exclude "**/build" \
  --exclude "**/.next" \
  --exclude "**/.expo" \
  --exclude "**/.git/objects" \
  --exclude "**/*.gguf" \
  --exclude "**/*.safetensors" \
  --exclude "**/*.bin" \
  --exclude "**/models" \
  --exclude "**/.DS_Store" \
  --exclude "**/pretrained_models" \
  --exclude "**/*.pth" \
  --exclude "**/*.ckpt" \
  --exclude "**/*.pt" \
  "$HOME/Developer"
rc=$?

# 共有 repo: 自ホストのスナップショットのみ間引き。prune は付けない (母艦が実施)。
restic forget --host "$HOST" \
  --keep-tag archive \
  --keep-daily 7 --keep-weekly 4 --keep-monthly 6 || true

echo "==================== $(date '+%F %T') backup done (rc=$rc) ===================="
if [ "$rc" -ne 0 ]; then
  notify "restic($HOST) ⚠️ バックアップ失敗 rc=$rc。ログ: $LOG"
fi
exit $rc
