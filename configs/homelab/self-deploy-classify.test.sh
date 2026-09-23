#!/usr/bin/env bash
# self-deploy.sh の切り分けロジックだけを取り出して確認する。
set -euo pipefail
classify() {
  local out="$1" rc=4
  failed_units=$(printf '%s\n' "$out" | sed -n 's/^warning: the following units failed: //p' | tr ',' '\n' | tr -d ' ')
  if [ -n "$failed_units" ]; then
    only_healthcheck=1
    while IFS= read -r unit; do
      [ -z "$unit" ] && continue
      printf '%s' "$unit" | grep -Eq '^[0-9a-f]{64}-[0-9a-f]+\.service$' || only_healthcheck=0
    done <<INNER
$failed_units
INNER
    [ "$only_healthcheck" = 1 ] && rc=0
  fi
  echo "$rc"
}
hc="caf48340918eafb2e550b51fcbf99399254d1c29e024cbeb9bc45c26665e18a4-5ff058df3d92ad01.service"
[ "$(classify "warning: the following units failed: $hc")" = 0 ] || { echo "NG: ヘルスチェック単独を成功にできていない"; exit 1; }
[ "$(classify "warning: the following units failed: nginx.service")" = 4 ] || { echo "NG: 本物の失敗を握り潰した"; exit 1; }
[ "$(classify "warning: the following units failed: $hc, nginx.service")" = 4 ] || { echo "NG: 混在を成功にした"; exit 1; }
[ "$(classify "error: something else")" = 4 ] || { echo "NG: 失敗行が無い場合"; exit 1; }
echo "OK: 4ケースとも期待どおり"
