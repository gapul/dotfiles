#!/usr/bin/env bash
# podman auto-update を回して、結果を ntfy に流す。
#
# 更新そのものは podman に任せる。pull → ユニット再起動 → 起動できなければ前の
# image に巻き戻して再起動、まで podman auto-update が持っている (--rollback は
# 既定で有効)。ここでやるのは「いつ回すか」と「何が起きたかを人に届けるか」だけで、
# 更新の手順を自前で書き直すことはしない。
#
# 鳴らすのは失敗と巻き戻しだけ。rolling tag のコンテナが多く、成功まで通知すると
# ほぼ毎日鳴って読まなくなる。起動後しばらくして落ちる型は journal-alert が拾う。
# 何を更新したかはジャーナルに残す (journalctl -u container-auto-update)。
set -uo pipefail

TOKEN_FILE=/var/lib/secrets/ntfy-alerts.token
NTFY_URL=http://127.0.0.1:8082/alerts

notify() {
  local title="$1" body="$2" prio="${3:-default}"
  curl -s -m 10 -o /dev/null \
    -H "Authorization: Bearer $(cat "$TOKEN_FILE")" \
    -H "Title: $title" -H "Priority: $prio" -H "Tags: package" \
    -d "$body" "$NTFY_URL" || true
}

out=$(podman auto-update --format json 2>&1)
rc=$?

if [ "$rc" -ne 0 ]; then
  notify "コンテナ更新が失敗した" "podman auto-update が exit $rc で終了した。

${out}" high
  exit 1
fi

# Updated は文字列で "false" / "true" / "failed" / "rolled back" が入る。
# "false" 以外は全部人に見せる。巻き戻しが起きたなら特に知りたい。
changed=$(printf '%s' "$out" |
  jq -r '[.[]? | select(.Updated != "false")] | .[] | "\(.Updated)\t\(.ContainerName // .Container)\t\(.Image)"' 2>/dev/null)

# 古い image が溜まり続けるので掃除する。auto-update 自体は消さない。
pruned=$(podman image prune -f 2>/dev/null | tail -1)

if [ -z "$changed" ]; then
  exit 0
fi

printf '%s\n' "$changed"
[ -n "$pruned" ] && printf '%s\n' "$pruned"

# 巻き戻しや失敗が無ければ黙る。
bad=$(printf '%s\n' "$changed" | grep -iE "fail|rolled")
[ -z "$bad" ] && exit 0

notify "コンテナの更新で失敗・巻き戻しが出た" "$(printf '%s' "$bad" | sed 's/\t/  /g')" high
