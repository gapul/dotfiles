#!/bin/bash
# Hermes ログローテーション (root で毎日 04:15 実行)
# launchd の StandardOutPath はプロセスが fd を持ち続けるため、
# 10MB を超えたログを退避したあと該当サービスを kickstart して付け替える。
set -u

LOGDIR=/Users/hermes/.hermes/logs
MAX=$((10 * 1024 * 1024))
KEEP=5

restart_gateway=0
restart_bridge=0
rotated=""

for f in gateway.log agent.log errors.log claude-bridge.log; do
  p="$LOGDIR/$f"
  [ -f "$p" ] || continue
  sz=$(stat -f%z "$p" 2>/dev/null || echo 0)
  [ "$sz" -ge "$MAX" ] || continue
  mv "$p" "$p.$(date +%Y%m%d)"
  rotated="$rotated $f"
  case "$f" in
    claude-bridge.log) restart_bridge=1 ;;
    *) restart_gateway=1 ;;
  esac
done

[ "$restart_gateway" = 1 ] && launchctl kickstart -k system/net.gapul.hermes-gateway
[ "$restart_bridge" = 1 ] && launchctl kickstart -k system/net.gapul.claude-bridge

# 再起動後に旧 fd への書き込みが落ち着いてから圧縮する
[ -n "$rotated" ] && sleep 5

for f in $rotated; do
  p="$LOGDIR/$f"
  for old in "$p".2*; do
    [ -f "$old" ] && [ "${old##*.}" != "gz" ] && gzip -f "$old"
  done
  # shellcheck disable=SC2012  # ログ名は自分で付けた 202601011234 形式なので ls で足りる
  ls -t "$p".2*.gz 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r g; do rm -f "$g"; done
done

exit 0
