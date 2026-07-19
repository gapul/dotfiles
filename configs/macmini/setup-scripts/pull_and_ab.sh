#!/bin/bash
export PATH="/run/current-system/sw/bin:$PATH"
export OLLAMA_HOST=127.0.0.1:11434
M="qwen2.5-coder:14b"
done_check(){ ollama list 2>/dev/null | grep -q "qwen2.5-coder"; }
echo "=== pulling $M (stall-watchdog) $(date +%H:%M:%S) ==="
while ! done_check; do
  ollama pull "$M" > /tmp/pull_coder.log 2>&1 &
  PID=$!
  last=$(du -sk ~/.ollama/models/blobs 2>/dev/null | cut -f1); stall=0
  while kill -0 $PID 2>/dev/null; do
    sleep 30
    cur=$(du -sk ~/.ollama/models/blobs 2>/dev/null | cut -f1)
    if [ "${cur:-0}" -le "${last:-0}" ]; then stall=$((stall+1)); else stall=0; fi
    last=$cur
    if [ $stall -ge 3 ]; then echo "stalled -> restart $(date +%H:%M:%S)"; kill $PID 2>/dev/null; wait $PID 2>/dev/null; break; fi
  done
  done_check && break
  sleep 5
done
echo "=== ALL LLMS PULLED $(date +%H:%M:%S) ==="

OUT=/tmp/llm_ab.log; : > "$OUT"
PROMPT="次の内容を、丁寧な敬語で2〜3文の議事録にまとめてください。箇条書きにせず自然な文章で。内容: 来週の新機能リリースについて議論した。既知のバグが2件残っており、田中が金曜日までに修正する予定。"
for m in "gemma4:12b-it-qat" "huihui_ai/qwen3-abliterated:14b" "qwen2.5-coder:14b"; do
  echo "############## $m ##############" >> "$OUT"
  t=$(date +%s)
  python3 ~/llm_ask.py "$m" "$PROMPT" >> "$OUT" 2>&1
  echo "" >> "$OUT"; echo "[elapsed $(( $(date +%s)-t ))s]" >> "$OUT"; echo "" >> "$OUT"
done
echo "=== LLM FINALIZE DONE $(date +%H:%M:%S) ===" >> "$OUT"
ollama list >> "$OUT" 2>&1
