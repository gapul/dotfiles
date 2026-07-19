#!/usr/bin/env bash
# rpi4 の docker サービスデータ (/home/pi) を共有 google-drive restic repo へ日次オフサイト。
# 共有 repo のため forget は --host スコープ + prune なし (prune は母艦の日次に委譲しロック競合回避)。
set -uo pipefail

export RCLONE_CONFIG=/root/.config/rclone/rclone.conf
export RESTIC_REPOSITORY="rclone:google-drive:restic-backup"
export RESTIC_PASSWORD_FILE=/root/.restic.pw

LOG=/var/log/restic-rpi-offsite.log
NTFY_URL_FILE=/root/.config/ntfy/url
NTFY_TOKEN_FILE=/root/.config/ntfy/token
HOST=$(hostname)

notify() {
  if [ -r "$NTFY_URL_FILE" ] && [ -r "$NTFY_TOKEN_FILE" ]; then
    curl -fsS --max-time 15 \
      -H "Authorization: Bearer $(cat "$NTFY_TOKEN_FILE")" \
      -H "Title: restic ($HOST)" -H "Priority: high" -H "Tags: warning" \
      -d "$1" "$(cat "$NTFY_URL_FILE")" >/dev/null 2>&1 || true
  fi
}

exec >>"$LOG" 2>&1
echo "==================== $(date '+%F %T') backup start ($HOST) ===================="

if ! rclone about google-drive: >/dev/null 2>&1; then
  echo "SKIP: google-drive リモート未到達 (トークン失効の可能性)"
  notify "restic($HOST) ⚠️ リモート未到達: google-drive 未認証の可能性。ログ確認: $LOG"
  exit 0
fi

if ! restic snapshots >/dev/null 2>&1; then
  echo "ERROR: repo にアクセスできない (パスワード/初期化?)"
  notify "restic($HOST) ⚠️ repo アクセス不可。ログ確認: $LOG"
  exit 1
fi

restic backup --verbose=1 \
  --exclude-caches \
  --exclude "**/node_modules" \
  --exclude "**/.venv" \
  --exclude "**/.direnv" \
  --exclude "**/*.tmp" \
  /home/pi
rc=$?

# 共有 repo: 自ホストのスナップショットのみ間引き。prune は付けない (母艦が実施)。
restic forget --host "$HOST" \
  --keep-tag archive \
  --keep-daily 7 --keep-weekly 4 --keep-monthly 6 || true

echo "==================== $(date '+%F %T') backup done (rc=$rc) ===================="
if [ "$rc" -ne 0 ]; then
  notify "restic($HOST) ⚠️ バックアップ失敗 rc=$rc。ログ確認: $LOG"
fi
exit $rc
