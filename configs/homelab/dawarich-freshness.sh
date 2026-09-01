#!/usr/bin/env bash
# 位置ログに新しい点が来ているかを見る。
#
# Dawarich の画面が開くことと、位置が記録されていることは別の話。2026-08-23 に
# 36 時間止まっていたのが見つかったが、そのあいだ web は普通に開いていた。
# 止まっていたのは iPhone 側の Overland で、サーバからは何も壊れて見えない。
#
# gatus は HTTP の応答しか見ないので、この形の停止は原理的に捕まえられない。
# 見るべきは「最後の点がいつか」で、restic の monitor が最後のスナップショットの
# 日付を見ているのと同じ考え方。
#
# 位置ログは取り直しが効かない。止まっていた期間は永久に空白になる。
set -uo pipefail

MAX_HOURS=${1:-24}
TOKEN_FILE=/var/lib/secrets/ntfy-alerts.token
NTFY_URL=http://127.0.0.1:8082/alerts

notify() {
  curl -s -m 10 -o /dev/null \
    -H "Authorization: Bearer $(cat "$TOKEN_FILE")" \
    -H "Title: $1" -H "Priority: high" -H "Tags: round_pushpin" \
    -d "$2" "$NTFY_URL" || true
}

latest=$(podman exec dawarich_db sh -c \
  'psql -U "$POSTGRES_USER" -d dawarich_production -tAc "select max(timestamp) from points"' \
  2>/dev/null | tr -d ' \r')

if [ -z "$latest" ]; then
  notify "位置ログ: DB を読めない" \
    "dawarich_db に問い合わせられなかった。コンテナが落ちているかもしれない"
  exit 1
fi

age_h=$(( ( $(date +%s) - latest ) / 3600 ))

if [ "$age_h" -ge "$MAX_HOURS" ]; then
  notify "位置ログが ${age_h} 時間止まっている" \
    "最後の点は $(date -d "@$latest" '+%Y-%m-%d %H:%M') 。iPhone の Overland を見ること —
送信先の URL、API キー、バックグラウンド更新、位置情報が「常に」になっているか。
止まっていた期間は取り直せない。"
  # ここで exit 1 しない。
  #
  # 「位置ログが止まっている」は監視の**結果**であって、監視そのものの失敗ではない。
  # 非ゼロで終わると systemd が dawarich-freshness.service を failed にするので、
  # 「落ちているユニット」の一覧に居座り、本当に壊れたユニットがそこに埋もれる。
  # 実際 2026-09-01 にそうなった (位置ログが 31 時間止まり、その通知は正しく飛んで
  # いたのに、ユニットの失敗として見えてしまい原因を追う手間が増えた)。
  #
  # 通知は既に出している。伝える手段はそちらで足りている。
  echo "位置ログが ${age_h} 時間止まっている (通知済み)"
  exit 0
fi

echo "OK: 最後の点は ${age_h} 時間前"
