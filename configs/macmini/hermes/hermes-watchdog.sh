#!/bin/bash
# Hermes 死活監視 (root で5分毎に実行)
# gateway プロセスを確認し、落ちていれば自動再起動。
# 再起動しても復旧しない場合のみ ntfy (alert.gapul.net/watchdog) に通知する。
# 状態遷移(ok→down / down→ok)のときだけ通知し、スパムを避ける。
set -u

ENV_FILE=/usr/local/etc/hermes-watchdog.env   # NTFY_URL / NTFY_TOKEN を定義
STATE=/var/run/hermes-watchdog.state
# shellcheck source=/dev/null
[ -f "$ENV_FILE" ] && . "$ENV_FILE"

notify() {  # $1=priority $2=message
  [ -n "${NTFY_URL:-}" ] || return 0
  curl -s -m 10 \
    -H "Authorization: Bearer ${NTFY_TOKEN:-}" \
    -H "Title: hermes-watchdog@macmini" \
    -H "Priority: $1" \
    -d "$2" "$NTFY_URL" >/dev/null 2>&1
}

check_gateway() {
  local pid
  pid=$(/usr/bin/python3 -c 'import json;print(json.load(open("/Users/hermes/.hermes/gateway.pid"))["pid"])' 2>/dev/null) || return 1
  kill -0 "$pid" 2>/dev/null
}

check_gateway_manabi() {
  local pid
  pid=$(/usr/bin/python3 -c 'import json;print(json.load(open("/Users/hermes/manabi-home/.hermes/gateway.pid"))["pid"])' 2>/dev/null) || return 1
  kill -0 "$pid" 2>/dev/null
}

failures=""
restarted=""

if ! check_gateway; then
  launchctl kickstart -k system/org.nixos.hermes-gateway 2>/dev/null
  launchctl kickstart -k system/org.nixos.hermes-gateway-manabi 2>/dev/null
  check_gateway_manabi || notify high "まなびの gateway を再起動した"
  restarted="gateway"
  sleep 20
  check_gateway || failures="gateway"
fi

# 標準出力はそのままログファイルへ流れる。以前はここに何も書いておらず、7月から 0 バイトの
# ままだった——おかげで watchdog 自身が壊れている(消したはずの claude-bridge を見張り続け、
# 存在しないラベルを kickstart していた)ことに誰も気づけなかった。動いた証跡は残す。
echo "[$(date '+%Y-%m-%d %H:%M:%S')] checked${restarted:+ restarted:$restarted}${failures:+ FAILED:$failures}"

prev=$(cat "$STATE" 2>/dev/null || echo ok)

if [ -n "$failures" ]; then
  cur="down:$failures"
  [ "$prev" != "$cur" ] && notify high "DOWN:$failures — 自動再起動も失敗。macmini を確認して"
  echo "$cur" > "$STATE"
else
  case "$prev" in
    down*) notify default "RECOVERED: hermes サービス復旧 (${restarted:-外的要因})" ;;
    *) [ -n "$restarted" ] && notify low "auto-restarted:$restarted (復旧済み)" ;;
  esac
  echo ok > "$STATE"
fi

exit 0
