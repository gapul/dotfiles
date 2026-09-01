#!/usr/bin/env bash
# main が進んでいたら自分で取りに行って切り替える。
#
# これまでは母艦から押し込んでいたが、その経路は母艦の ssh 鍵に依存していた。
# 常用鍵を Secure Enclave に移してから、鍵が Touch ID の承認を要求するように
# なり、無人のときは押し込めない。2026-08-30 に承認の窓が切れて実際に止まった。
#
# 押す側の資格情報を要らなくするのが目的なので、鍵を足すのではなく向きを変える。
# homeserver は公開 flake を読むだけでよく、誰の鍵も要らない。母艦が壊れていても
# 出かけていても、マージされた設定は反映される。
#
# 安全性は main の側で担保する。github: の参照は main を指し、main は CI を
# 通ったものしか入らない。切り替えに失敗すれば nixos-rebuild が失敗して古い世代の
# まま残る。起動はしたが中身が壊れている型は journal-alert の再起動ループ検知が拾う。
set -uo pipefail

FLAKE="github:gapul/dotfiles?dir=nix#homeserver"
REPO=https://github.com/gapul/dotfiles
STATE=/var/lib/self-deploy/deployed-rev
ALERTED=/var/lib/self-deploy/alerted-rev

TOKEN_FILE=/var/lib/secrets/ntfy-alerts.token
NTFY_URL=http://127.0.0.1:8082/alerts

notify() {
  local title="$1" body="$2" prio="${3:-default}"
  curl -s -m 10 -o /dev/null \
    -H "Authorization: Bearer $(cat "$TOKEN_FILE")" \
    -H "Title: $title" -H "Priority: $prio" -H "Tags: package" \
    -d "$body" "$NTFY_URL" || true
}

mkdir -p "$(dirname "$STATE")"

remote=$(git ls-remote "$REPO" HEAD 2>/dev/null | awk '{print $1}')
if [ -z "$remote" ]; then
  # 取れないのは大抵ネットワークの一時的な問題。次の周回で拾えるので黙る。
  exit 0
fi

[ "$remote" = "$(cat "$STATE" 2>/dev/null)" ] && exit 0

# --refresh が要る。github: の flake 参照はキャッシュされるので、付けないと
# マージ直後に古い revision へ切り替わる (実害を出したことがある)。
out=$(nixos-rebuild switch --refresh --flake "$FLAKE" 2>&1)
rc=$?

if [ "$rc" -eq 0 ]; then
  printf '%s' "$remote" > "$STATE"
  notify "homeserver を ${remote:0:8} に更新した" "$(printf '%s' "$out" | tail -3)"
  exit 0
fi

# 失敗の中身をジャーナルにも残す。通知にしか出さないと、あとから
# `journalctl -u self-deploy` を見ても「失敗した」としか分からず、原因を追うのに
# 手で再現する羽目になる (2026-09-01 に踏んだ)。通知は要約、ジャーナルは全文。
printf '%s\n' "$out" >&2

# 失敗したら state を進めない。次の周回で再試行する。ただし同じ revision で
# 鳴り続けると読まなくなるので、通知は revision ごとに 1 回だけにする。
if [ "$remote" != "$(cat "$ALERTED" 2>/dev/null)" ]; then
  printf '%s' "$remote" > "$ALERTED"
  notify "homeserver の自動更新が失敗した (${remote:0:8})" "exit $rc。古い世代のまま動いている。

$(printf '%s' "$out" | tail -12)" high
fi
exit 1
