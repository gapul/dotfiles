#!/bin/bash
export PATH="/opt/homebrew/bin:$PATH"
: > /tmp/rag_dl.log
until aria2c -c -j4 -x8 -s8 -k1M --max-tries=5 --retry-wait=8 --lowest-speed-limit=1 \
      --connect-timeout=20 --timeout=30 --file-allocation=none --console-log-level=warn \
      -i /tmp/rag_urls.txt >> /tmp/rag_dl.log 2>&1; do
  echo "=== aria2 exit non-zero, resume $(date +%H:%M:%S) ===" >> /tmp/rag_dl.log
  sleep 3
done
echo "RAG_DL_DONE" >> /tmp/rag_dl.log
