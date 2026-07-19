#!/bin/bash
export PATH="/opt/homebrew/bin:$PATH"
~/rag_dl_robust.sh &
DLPID=$!
last=0; stall=0
while kill -0 $DLPID 2>/dev/null; do
  sleep 30
  cur=$(du -sk ~/rag-models 2>/dev/null|cut -f1)
  if [ "${cur:-0}" -le "$last" ]; then stall=$((stall+1)); else stall=0; fi
  last=$cur
  if [ $stall -ge 2 ]; then echo "watchdog: stall検知→aria2再起動" >> /tmp/rag_dl.log; pkill -f "aria2c.*rag_urls"; stall=0; fi
done
# 完了後に検証
sleep 3
echo "=== 検証 ===" 
~/rag-venv/bin/python ~/rag_test.py 2>&1 | grep -vE "warning|Warning|^\s*$" | tail -18
echo "=== RAG FINALIZE DONE ==="
