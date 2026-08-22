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

# ── 会話の合成監視 ─────────────────────────────────────────────
# プロセスの生死だけ見ていても「生きているのに答えられない」は捕まらない
# (tar 破損・read_file の重複判定・ガードレール閾値で、1週間に3回それが起きた)。
# 3時間おきに1回、まなびに実際の質問を投げ、まともな返事が返るかを見る。
CANARY_STAMP=/var/run/hermes-canary.stamp
CANARY_INTERVAL=10800

check_canary() {
  local now last env key port reply
  now=$(date +%s)
  last=$(cat "$CANARY_STAMP" 2>/dev/null || echo 0)
  [ $((now - last)) -lt "$CANARY_INTERVAL" ] && return 0
  echo "$now" > "$CANARY_STAMP"
  env=/Users/hermes/manabi-home/.hermes/.env
  key=$(grep '^API_SERVER_KEY=' "$env" 2>/dev/null | cut -d= -f2-)
  port=$(grep '^API_SERVER_PORT=' "$env" 2>/dev/null | cut -d= -f2-)
  [ -n "$key" ] || return 0   # 設定が読めないときは判定しない
  reply=$(curl -s -m 280 -X POST "http://127.0.0.1:${port:-8791}/v1/chat/completions" \
    -H "Content-Type: application/json" -H "Authorization: Bearer $key" \
    -d '{"model":"manabi","messages":[{"role":"user","content":"監視用の自動確認です。progress.md を読んで、いちばん近い締切をひとことで。"}]}' \
    | /usr/bin/python3 -c 'import json,sys
try:
    print(json.load(sys.stdin)["choices"][0]["message"]["content"][:400])
except Exception:
    pass')
  case "$reply" in
    "") return 1 ;;
    *guardrail*|*"claude-acp error"*|*halted*) return 1 ;;
  esac
  return 0
}

# hermes-brain に秘密や生成物が紛れていないかを毎回見る。tar の除外ミスで
# 資格情報が1か月コミットされ続けた事故の再発防止。
check_brain_clean() {
  sudo -u hermes git -C /Users/hermes/hermes-brain ls-files 2>/dev/null \
    | grep -qE '(^|/)\.(dashboard_auth|gcal_client\.json|gcal_token\.json|studyplus[a-z_]*\.json)$|\.env$' \
    && return 1
  return 0
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

if ! check_canary; then
  # 会話が壊れているとき、プロセス再起動で直る類(重複判定のカウンタ等)がある。
  # 一度だけ再起動して再試行し、それでもだめなら鳴らす。
  launchctl kickstart -k system/org.nixos.hermes-gateway-manabi 2>/dev/null
  sleep 30
  rm -f "$CANARY_STAMP"   # 再試行を許す
  if ! check_canary; then
    failures="${failures:+$failures,}canary"
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] canary failed once, recovered by restart"
    notify default "canary: まなびの応答が壊れていたが再起動で復旧"
  fi
fi

check_brain_clean || failures="${failures:+$failures,}brain-secrets"

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
