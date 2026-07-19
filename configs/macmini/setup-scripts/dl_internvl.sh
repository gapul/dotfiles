#!/bin/bash
export PATH="/opt/homebrew/bin:$PATH"
n=0
while true; do
  n=$((n+1)); echo "=== pass $n $(date +%H:%M:%S) ==="
  aria2c -c -j4 -x8 -s8 -k1M --max-tries=10 --retry-wait=8 \
    --lowest-speed-limit=0 --max-connection-per-server=8 \
    --file-allocation=none --console-log-level=warn --summary-interval=30 \
    -i /tmp/internvl_urls.txt
  [ $? -eq 0 ] && break
  sleep 5
done
echo "=== INTERNVL MODEL DOWNLOADED $(date +%H:%M:%S) ==="
du -sh /Users/gapul/models/internvl3-8b-4bit
