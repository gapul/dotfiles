#!/usr/bin/env bash
# Caddy の vhost 一覧と Cloudflare の A レコードを突き合わせる。
#
#   scripts/check-dns-drift.sh          # 差分を出す。足りなければ exit 1
#   scripts/check-dns-drift.sh --apply  # 足りないものを作り、宛先違いを直す
#   scripts/check-dns-drift.sh --json   # 機械向け
#
# hosts/homeserver.nix の sites 表は reverse proxy と死活監視の SSOT になっているのに、
# DNS だけ手作業で取り残されていた。サービスを足すたびに「A レコードを追加」を
# 手順書に書き足す運用で、1 件取りこぼすと「そのサービスだけ繋がらない」を後日踏む。
# vhost が在るなら A レコードも在るべき、という当たり前を機械に見せる。
#
# 宛先は tailnet の homeserver。*.gapul.net は全件そこを指し、proxied=false で
# CF を通さない (tailnet の中でしか届かないアドレスなので、通しても意味が無い)。
set -euo pipefail

repo=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
flake="$repo/nix"
zone_name="gapul.net"

apply=false
json=false
for arg in "$@"; do
  case "$arg" in
  --apply) apply=true ;;
  --json) json=true ;;
  *)
    echo "usage: check-dns-drift.sh [--apply] [--json]" >&2
    exit 2
    ;;
  esac
done

need() {
  command -v "$1" >/dev/null || {
    echo "$1 が無い" >&2
    exit 1
  }
}
need nix
need jq
need curl

# 宛先は tailnet 上の homeserver。Tailscale が割り当てるので nix には書けない。
target=$(tailscale status --json 2>/dev/null |
  jq -r '.Peer[]? | select(.DNSName | startswith("homeserver.")) | .TailscaleIPs[0]' | head -1)
if [[ -z ${target:-} ]]; then
  echo "tailnet に homeserver が見えない (Tailscale に繋がっているか確認)" >&2
  exit 1
fi

# 期待するレコード = Caddy が実際に建てる vhost。sites 表を直接読まずに
# 生成後の virtualHosts を見るのは、表の書き方が変わっても追従させるため。
mapfile -t expected < <(
  nix eval --json "$flake#nixosConfigurations.homeserver.config.services.caddy.virtualHosts" \
    --apply 'builtins.attrNames' | jq -r '.[]' | sort
)

token=$(nix develop "$flake" -c sops -d --extract '["cloudflare"]["api_token"]' "$repo/secrets/secrets.yaml" 2>/dev/null || true)
if [[ -z ${token:-} ]]; then
  echo "sops から cloudflare.api_token を取れない (age 鍵がある環境で実行する)" >&2
  exit 1
fi

cf() {
  # トークンは引数に出さない。ps から見えるし、set -x でも漏れる。
  curl -fsS -H "Authorization: Bearer ${token}" -H "Content-Type: application/json" "$@"
}
api="https://api.cloudflare.com/client/v4"

zone_id=$(cf "${api}/zones?name=${zone_name}" | jq -r '.result[0].id')
[[ -n $zone_id && $zone_id != "null" ]] || {
  echo "zone ${zone_name} が引けない (トークンに Zone:Read が要る)" >&2
  exit 1
}

# name -> "id content" の対応表。1 回だけ引いてループで使い回す。
records=$(cf "${api}/zones/${zone_id}/dns_records?type=A&per_page=500" |
  jq -r '.result[] | "\(.name)\t\(.id)\t\(.content)"')

missing=() wrong=() ok=()
for host in "${expected[@]}"; do
  # awk で引く。grep -P は macOS では期待どおり動かず、全件 MISSING の誤報になった。
  line=$(awk -F'\t' -v h="$host" '$1 == h { print; exit }' <<<"$records")
  if [[ -z $line ]]; then
    missing+=("$host")
    continue
  fi
  content=$(cut -f3 <<<"$line")
  if [[ $content != "$target" ]]; then
    wrong+=("${host}\t${content}")
  else
    ok+=("$host")
  fi
done

# vhost に無い A レコードは報告だけ。apex や CF Pages 向けなど、Caddy を
# 通らない正当なレコードが同じ zone に同居している。
extra=()
while IFS=$'\t' read -r name _ _; do
  [[ -z ${name:-} ]] && continue
  printf '%s\n' "${expected[@]}" | grep -qx "$name" || extra+=("$name")
done <<<"$records"

if $json; then
  jq -n --arg target "$target" \
    --argjson missing "$(printf '%s\n' "${missing[@]+"${missing[@]}"}" | jq -Rsc 'split("\n") | map(select(length > 0))')" \
    --argjson wrong "$(printf '%b\n' "${wrong[@]+"${wrong[@]}"}" | cut -f1 | jq -Rsc 'split("\n") | map(select(length > 0))')" \
    --argjson extra "$(printf '%s\n' "${extra[@]+"${extra[@]}"}" | jq -Rsc 'split("\n") | map(select(length > 0))')" \
    '{target: $target, missing: $missing, wrong: $wrong, extra: $extra}'
  exit 0
fi

echo "宛先: ${target} (tailnet の homeserver)"
echo "━━━ vhost が在るのに A レコードが無い ━━━"
if [[ ${#missing[@]} -eq 0 ]]; then
  echo "  なし"
else
  for h in "${missing[@]}"; do
    echo "  MISSING  $h"
    if $apply; then
      cf -X POST "${api}/zones/${zone_id}/dns_records" \
        --data "$(jq -n --arg n "$h" --arg c "$target" \
          '{type:"A", name:$n, content:$c, ttl:60, proxied:false}')" >/dev/null
      echo "    作成した"
    fi
  done
fi

echo "━━━ 宛先が違う ━━━"
if [[ ${#wrong[@]} -eq 0 ]]; then
  echo "  なし"
else
  for w in "${wrong[@]}"; do
    IFS=$'\t' read -r host content <<<"$(printf '%b' "$w")"
    echo "  WRONG    $host: $content -> $target"
    if $apply; then
      id=$(awk -F'\t' -v h="$host" '$1 == h { print $2; exit }' <<<"$records")
      cf -X PATCH "${api}/zones/${zone_id}/dns_records/${id}" \
        --data "$(jq -n --arg c "$target" '{content:$c}')" >/dev/null
      echo "    直した"
    fi
  done
fi

echo "━━━ vhost に無い A レコード (参考) ━━━"
if [[ ${#extra[@]} -eq 0 ]]; then
  echo "  なし"
else
  printf '  %s\n' "${extra[@]}"
fi

echo "一致: ${#ok[@]} 件 / 宣言 ${#expected[@]} 件"
# EXTRA では落とさない。apex や Pages 向けのレコードが正当に同居している。
if ! $apply && { [[ ${#missing[@]} -gt 0 ]] || [[ ${#wrong[@]} -gt 0 ]]; }; then
  echo "DNS が宣言に追いついていない。--apply で寄せる" >&2
  exit 1
fi
