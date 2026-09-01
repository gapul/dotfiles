#!/usr/bin/env bash
# 動いている構成に既知の脆弱性が無いかを見る。
#
# ローリングに切り替えたので「見つかったら直す」が方針になったが、**見つける経路が
# 無かった**。上流が直しても、こちらがそれを知る手段が人の耳しかない状態だった。
# vulnix は現在の system closure を NVD と突き合わせるので、そこが埋まる。
#
# 直すのは別系統でよい。update-flake-lock が毎時走って CI を通ってから self-deploy が
# 取りに行くので、上流に修正が入っていれば最悪 2 時間で当たる。ここがやるのは
# 「まだ当たっていないものを知らせる」ことだけ。
#
# 鳴りすぎると読まなくなるので、同じ顔ぶれでは 1 日 1 回までにする。
set -uo pipefail

STATE=/var/lib/vulnix/last-report
TOKEN_FILE=/var/lib/secrets/ntfy-alerts.token
NTFY_URL=http://127.0.0.1:8082/alerts

notify() {
  curl -s -m 10 -o /dev/null \
    -H "Authorization: Bearer $(cat "$TOKEN_FILE")" \
    -H "Title: $1" -H "Priority: ${3:-default}" -H "Tags: lock" \
    -d "$2" "$NTFY_URL" || true
}

mkdir -p "$(dirname "$STATE")"

# 稼働中の世代そのものを見る。-w で whitelist が無くても動く。
out=$(vulnix --system /run/current-system 2>/dev/null)
rc=$?

# vulnix は「見つかった」ときに非ゼロで終わる。0 なら何も無い。
if [ "$rc" -eq 0 ]; then
  : > "$STATE"
  exit 0
fi

# 影響を受けたパッケージ名だけを取り出して指紋にする。CVE が増減しても同じ
# パッケージ群なら鳴らし直さない。
fingerprint=$(printf '%s' "$out" | grep -oE '^[a-zA-Z0-9._+-]+-[0-9][^ ]*' | sort -u | tr '\n' ' ')
[ -z "$fingerprint" ] && exit 0

if [ "$fingerprint" = "$(cat "$STATE" 2>/dev/null)" ]; then
  exit 0
fi
printf '%s' "$fingerprint" > "$STATE"

count=$(printf '%s' "$fingerprint" | wc -w | tr -d ' ')
notify "既知の脆弱性を持つパッケージが ${count} 件" "$(printf '%s' "$out" | head -40)

修正が上流に入っていれば update-flake-lock (毎時) が拾う。
入っていないなら、そのパッケージだけ先に上げるか、使用をやめるかの判断が要る。" high
