#!/bin/bash
# コンテナのポートをホストへ公開する。
# socat は macOS 26 の Local Network 制限で launchd 配下だと EHOSTUNREACH になるため、
# self-ssh の -L 転送に変更 (2026-07-18)。vmnet への外向き接続は sshd (remote-login
# 文脈 = Local Network 制限の適用除外) が行うので、どの文脈から起動しても通る。
# container 1.1.0 の -p は listener だけ立って転送しない罠があり使えない。
eval "$(/opt/homebrew/bin/brew shellenv)"
MAP="anythingllm:3001:3001 open-webui:3000:8080"
pkill -f "id_selffwd" 2>/dev/null
pkill -f "socat.*TCP-LISTEN" 2>/dev/null  # 旧方式の残骸掃除
sleep 1
FWD=()
for m in $MAP; do
  nm="${m%%:*}"; rest="${m#*:}"; hp="${rest%%:*}"; cp="${rest##*:}"
  ip=$(container list 2>/dev/null | awk -v n="$nm" "\$1==n{print \$6}" | cut -d/ -f1)
  [ -z "$ip" ] && { echo "$nm: 未起動、スキップ"; continue; }
  FWD+=(-L "0.0.0.0:$hp:$ip:$cp")
  echo "$nm: host:$hp -> $ip:$cp"
done
[ ${#FWD[@]} -eq 0 ] && exit 0
/usr/bin/ssh -f -N -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=accept-new \
  -o ServerAliveInterval=30 -i ~/.ssh/id_selffwd "${FWD[@]}" gapul@127.0.0.1
