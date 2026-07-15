#!/bin/bash
eval "$(/opt/homebrew/bin/brew shellenv)"
MAP="anythingllm:3001:3001 open-webui:3000:8080"
pkill -f "socat TCP-LISTEN" 2>/dev/null; sleep 1
for m in $MAP; do
  nm="${m%%:*}"; rest="${m#*:}"; hp="${rest%%:*}"; cp="${rest##*:}"
  ip=$(container list 2>/dev/null | awk -v n="$nm" "\$1==n{print \$6}" | cut -d/ -f1)
  [ -z "$ip" ] && { echo "$nm: 未起動、スキップ"; continue; }
  nohup socat TCP-LISTEN:$hp,fork,reuseaddr TCP:$ip:$cp >/dev/null 2>&1 &
  echo "$nm: host:$hp -> $ip:$cp"
done
