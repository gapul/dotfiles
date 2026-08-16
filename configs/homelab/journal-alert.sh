#!/usr/bin/env bash
# journald を追いかけて、壊れたときの合図を ntfy に流す。
#
# 収集そのものは要らない。全コンテナが log-driver=journald なので、ログは既に
# 1 箇所に集まっている。足りないのは「誰も見に行かない」ことの方で、
# 2026-08-16 に見つかった 6 件はどれも何日もログに書かれ続けていた。
#
# 誤検知で鳴り続けると読まなくなるので、拾うのは「放置すると壊れたままになる」
# ものだけに絞る。単発の ERROR は拾わない。
set -uo pipefail

TOKEN_FILE=/var/lib/secrets/ntfy-alerts.token
NTFY_URL=http://127.0.0.1:8082/alerts

notify() {
  local title="$1" body="$2" prio="${3:-default}"
  curl -s -m 10 -o /dev/null \
    -H "Authorization: Bearer $(cat "$TOKEN_FILE")" \
    -H "Title: $title" -H "Priority: $prio" -H "Tags: warning" \
    -d "$body" "$NTFY_URL" || true
}

# 拾う合図。左が journald の検索語、右が通知の見出し。
# grep -F の固定文字列で見る (正規表現にすると誤爆が増える)。
declare -a PATTERNS=(
  "Activating recovery mode|Home Assistant が recovery mode に落ちた"
  "stale sessions detected|free-games-claimer のストアセッションが切れた"
  "refusing to access private network|miniflux が自前 RSSHub を読めていない"
  "Failed to establish secure session|Matter のペアリングに失敗している"
  "Discovery timed out|Matter がデバイスを見つけられない"
  "permission denied|権限まわりで拒否されている"
)

SINCE="${1:--15min}"

for entry in "${PATTERNS[@]}"; do
  needle="${entry%%|*}"
  label="${entry#*|}"
  hits=$(journalctl --since "$SINCE" --no-pager 2>/dev/null | grep -cF "$needle")
  if [ "${hits:-0}" -gt 0 ]; then
    sample=$(journalctl --since "$SINCE" --no-pager 2>/dev/null | grep -F "$needle" | tail -1 | cut -c1-200)
    notify "$label" "直近 ${SINCE#-} で ${hits} 件
${sample}" high
  fi
done

# 落ちたユニット。systemd が知っているのに誰も見ていない典型。
failed=$(systemctl --failed --no-legend | awk '{print $1}' | tr '\n' ' ')
if [ -n "${failed// /}" ]; then
  notify "failed unit がある" "$failed" high
fi

# restic の鮮度。転送が黙って止まるのはこの構成で実績がある
# (rclone の Google Drive トークンが 1 週間で失効する)。
if systemctl is-failed --quiet restic-backups-homeserver.service; then
  notify "restic のバックアップが失敗している" "systemctl status restic-backups-homeserver" high
fi
