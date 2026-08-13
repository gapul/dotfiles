#!/usr/bin/env bash
# tailnet のポリシーファイル (ACL / Split DNS / タグ) を repo に置いて往復させる。
#
#   scripts/tailscale-policy.sh fetch   # 管理コンソールの現物を repo に落とす
#   scripts/tailscale-policy.sh diff    # repo と現物の差分
#   scripts/tailscale-policy.sh apply   # repo の内容を管理コンソールへ
#
# ACL も Split DNS も管理コンソールにしか無く、repo には一文字も無かった。
# gapul.net の名前解決を Split DNS で直した経緯も、どこにも残っていない。
# Syncthing や Caddy でやったのと同じで、Web UI ではなく commit を真実にする。
#
# 認証は API アクセストークン (admin console → Settings → Keys → API access token)。
#   export TS_API_KEY=tskey-api-...
# tailscale CLI にはポリシーを読む口が無いので、ここは API を直接叩く。
set -euo pipefail

repo=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
file="$repo/tailscale/policy.hujson"
# "-" は「このトークンが属する tailnet」を指す。組織名を repo に書かずに済む。
api="https://api.tailscale.com/api/v2/tailnet/-/acl"

if [[ -z ${TS_API_KEY:-} ]]; then
  echo "TS_API_KEY が無い。admin console → Settings → Keys で作る" >&2
  exit 1
fi

# HuJSON (コメント付き JSON) のまま扱う。コメントを落とすと、なぜその ACL なのかが
# 消える。Accept ヘッダで HuJSON を要求しないと素の JSON が返る。
#
# 認証は Bearer。basic 認証の書き方でも通るが、秘密検出の規則に毎回引っかかる
# (中身は変数なので実際には何も漏れない) ので、素直にヘッダで送る。
ts() { curl -fsS -H "Authorization: Bearer ${TS_API_KEY}" -H "Accept: application/hujson" "$@"; }

case "${1:-diff}" in
fetch)
  mkdir -p "$(dirname "$file")"
  ts "$api" >"$file"
  echo "落とした: ${file#"$repo"/}"
  ;;
diff)
  [[ -f $file ]] || {
    echo "$file が無い。まず fetch" >&2
    exit 1
  }
  tmp=$(mktemp)
  trap 'rm -f "$tmp"' EXIT
  ts "$api" >"$tmp"
  if diff -u "$tmp" "$file" >/dev/null; then
    echo "一致"
  else
    diff -u --label "live" --label "repo" "$tmp" "$file" || true
    echo "管理コンソールと repo がずれている" >&2
    exit 1
  fi
  ;;
apply)
  [[ -f $file ]] || {
    echo "$file が無い" >&2
    exit 1
  }
  # If-Match を付けないと、他所で編集された内容を黙って上書きする。
  # 取得した etag と食い違えば Tailscale 側が弾く。
  etag=$(ts -I "$api" | awk 'tolower($1) == "etag:" { print $2 }' | tr -d '\r"')
  ts -X POST "$api" \
    -H "Content-Type: application/hujson" \
    ${etag:+-H "If-Match: \"${etag}\""} \
    --data-binary "@${file}" >/dev/null
  echo "適用した"
  ;;
*)
  echo "usage: tailscale-policy.sh [fetch|diff|apply]" >&2
  exit 2
  ;;
esac
