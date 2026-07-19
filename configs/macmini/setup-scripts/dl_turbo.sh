#!/bin/bash
set -u
export PATH="/opt/homebrew/bin:$PATH"
D="$HOME/models/whisper-large-v3-turbo-mlx"
BASE="https://huggingface.co/mlx-community/whisper-large-v3-turbo/resolve/main"
mkdir -p "$D"
cat > /tmp/turbo_urls.txt <<EOF
$BASE/config.json
  out=config.json
$BASE/weights.safetensors
  out=weights.safetensors
EOF
n=0
while true; do
  n=$((n+1)); echo "=== pass $n $(date +%H:%M:%S) ==="
  aria2c -c -j2 -x8 -s8 -k1M --max-tries=10 --retry-wait=8 \
    --lowest-speed-limit=0 --max-connection-per-server=8 \
    --file-allocation=none --console-log-level=warn --summary-interval=30 \
    --dir="$D" -i /tmp/turbo_urls.txt
  rc=$?
  if [ $rc -eq 0 ]; then echo "=== TURBO DOWNLOAD COMPLETE $(date +%H:%M:%S) ==="; break; fi
  sleep 5
done
ls -l "$D"
