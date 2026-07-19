#!/bin/bash
eval "$(/opt/homebrew/bin/brew shellenv)"
# open-webuiコンテナの:8080が応答するまで待つ→socat転送→確認
for i in $(seq 1 120); do
  ip=$(container list 2>/dev/null | awk "\$1==\"open-webui\"{print \$6}" | cut -d/ -f1)
  if [ -n "$ip" ] && [ "$(curl -s -o /dev/null -w %{http_code} --max-time 6 http://$ip:8080/ 2>/dev/null)" = "200" ]; then
    ~/container_proxy.sh
    sleep 3
    r=$(curl -s -o /dev/null -w %{http_code} --max-time 6 http://192.168.116.91:3000/ 2>/dev/null)
    echo "OPENWEBUI READY LAN:3000=$r $(date +%H:%M:%S)"
    exit 0
  fi
  sleep 30
done
echo "OPENWEBUI TIMEOUT"
