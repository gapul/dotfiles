#!/usr/bin/env bash
# gapul.net の A レコードを、旧 IP から新 IP へまとめて付け替える。
#
# homeserver 移行で必要になる。*.gapul.net は全件 Caddy の tailnet IP を指していて、
# Caddy が別ホストへ移ると tailnet IP が変わるため、20件超を手で直すことになる。
# 1件でも取りこぼすと「そのサービスだけ繋がらない」を後日踏む。
#
# 既定は dry-run。--apply を付けたときだけ実際に PATCH する。
#
# 使い方:
#   export CF_API_TOKEN=...            # Zone:DNS:Edit 権限
#   scripts/cf-repoint-records.sh --from 100.64.125.107 --to 100.x.y.z
#   scripts/cf-repoint-records.sh --from 100.64.125.107 --to 100.x.y.z --apply
set -euo pipefail

zone_name="gapul.net"
from_ip=""
to_ip=""
apply=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --zone) zone_name="$2"; shift 2 ;;
    --from) from_ip="$2"; shift 2 ;;
    --to) to_ip="$2"; shift 2 ;;
    --apply) apply=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$from_ip" || -z "$to_ip" ]]; then
  echo "usage: $0 --from <old-ip> --to <new-ip> [--zone gapul.net] [--apply]" >&2
  exit 2
fi
: "${CF_API_TOKEN:?CF_API_TOKEN が未設定 (Zone:DNS:Edit 権限のトークン)}"

api() {
  curl -sS -H "Authorization: Bearer ${CF_API_TOKEN}" -H "Content-Type: application/json" "$@"
}

# zone id はリポジトリに書かず、ゾーン名から都度引く。
zone_id=$(api "https://api.cloudflare.com/client/v4/zones?name=${zone_name}" |
  jq -r '.result[0].id // empty')
if [[ -z "$zone_id" ]]; then
  echo "zone が見つからない: ${zone_name} (トークンの権限を確認)" >&2
  exit 1
fi

# 該当レコードを集める。ページングは 100 件/頁で足りる規模だが、念のため辿る。
records=$(
  page=1
  while :; do
    body=$(api "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records?type=A&per_page=100&page=${page}")
    echo "$body" | jq -c --arg ip "$from_ip" '.result[] | select(.content == $ip) | {id, name, proxied, ttl}'
    total=$(echo "$body" | jq -r '.result_info.total_pages // 1')
    ((page >= total)) && break
    page=$((page + 1))
  done
)

count=$(printf '%s' "$records" | grep -c . || true)
if [[ "$count" -eq 0 ]]; then
  echo "${from_ip} を指す A レコードは無い。すでに移行済みか、IP が違う。"
  exit 0
fi

echo "${zone_name}: ${from_ip} → ${to_ip} に付け替える A レコード ${count} 件"
printf '%s\n' "$records" | jq -r '"  " + .name'

if [[ "$apply" -eq 0 ]]; then
  echo
  echo "dry-run。実行するには --apply を付ける。"
  exit 0
fi

failed=0
while read -r rec; do
  [[ -z "$rec" ]] && continue
  id=$(echo "$rec" | jq -r .id)
  name=$(echo "$rec" | jq -r .name)
  payload=$(echo "$rec" | jq -c --arg ip "$to_ip" '{type:"A", name:.name, content:$ip, ttl:.ttl, proxied:.proxied}')
  ok=$(api -X PUT --data "$payload" \
    "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records/${id}" | jq -r '.success')
  if [[ "$ok" == "true" ]]; then
    echo "  ok   ${name}"
  else
    echo "  FAIL ${name}" >&2
    failed=1
  fi
done <<< "$records"

exit "$failed"
