#!/usr/bin/env bash
# NextDNS のプロファイル設定 (ブロックリスト / 書き換え / 許可リスト) を repo に置く。
#
#   scripts/nextdns-profile.sh fetch   # 現物を repo に落とす
#   scripts/nextdns-profile.sh diff    # repo と現物の差分
#   scripts/nextdns-profile.sh apply   # repo の内容を NextDNS へ
#
# iOS も Android も母艦も DNS はここを通っているのに、設定は Web UI にしか無い。
# ブロックリストを 1 つ足したことも、gapul.net の rebinding を許した設定も、
# 履歴が残らない。ここを commit にすると、なぜその例外があるのかが追える。
#
# 認証は API キー (my.nextdns.io → Account → API)。プロファイル ID は
# 設定画面の URL 末尾 (6 文字)。どちらも repo には入れない。
#   export NEXTDNS_API_KEY=...
#   export NEXTDNS_PROFILE=abc123
set -euo pipefail

repo=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
file="$repo/nextdns/profile.json"

for v in NEXTDNS_API_KEY NEXTDNS_PROFILE; do
  [[ -n ${!v:-} ]] || {
    echo "$v が無い (my.nextdns.io → Account → API)" >&2
    exit 1
  }
done
api="https://api.nextdns.io/profiles/${NEXTDNS_PROFILE}"

nd() { curl -fsS -H "X-Api-Key: ${NEXTDNS_API_KEY}" -H "Content-Type: application/json" "$@"; }

# 差分を読める形にするため常に整形して置く。API の返す順序は安定しないので、
# キーを並べ替えてから比べる (並びだけで差分が出ると誰も見なくなる)。
normalize() { jq -S '.data // .'; }

case "${1:-diff}" in
fetch)
  mkdir -p "$(dirname "$file")"
  nd "$api" | normalize >"$file"
  echo "落とした: ${file#"$repo"/}"
  ;;
diff)
  [[ -f $file ]] || {
    echo "$file が無い。まず fetch" >&2
    exit 1
  }
  tmp=$(mktemp)
  trap 'rm -f "$tmp"' EXIT
  nd "$api" | normalize >"$tmp"
  if diff -u "$tmp" "$file" >/dev/null; then
    echo "一致"
  else
    diff -u --label "live" --label "repo" "$tmp" "$file" || true
    echo "NextDNS と repo がずれている" >&2
    exit 1
  fi
  ;;
apply)
  [[ -f $file ]] || {
    echo "$file が無い" >&2
    exit 1
  }
  # PATCH は部分更新。プロファイル全体を PUT で置き換える口は無いので、
  # repo にしか無い設定は反映されるが、NextDNS 側の余分は消えない。
  nd -X PATCH "$api" --data-binary "@${file}" >/dev/null
  echo "適用した (repo に無い設定は NextDNS 側に残る)"
  ;;
*)
  echo "usage: nextdns-profile.sh [fetch|diff|apply]" >&2
  exit 2
  ;;
esac
