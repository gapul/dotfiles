#!/bin/bash
export PATH="/run/current-system/sw/bin:$PATH"
export OLLAMA_HOST=127.0.0.1:11434
pull_one(){
  local M="$1" key="$2"
  ollama list 2>/dev/null | grep -q "$key" && { echo "$M already"; return; }
  while ! ollama list 2>/dev/null | grep -q "$key"; do
    ollama pull "$M" > /tmp/pull_unc.log 2>&1 &
    local PID=$! last cur stall=0
    last=$(du -sk ~/.ollama/models/blobs 2>/dev/null | cut -f1)
    while kill -0 $PID 2>/dev/null; do
      sleep 30; cur=$(du -sk ~/.ollama/models/blobs 2>/dev/null | cut -f1)
      if [ "${cur:-0}" -le "${last:-0}" ]; then stall=$((stall+1)); else stall=0; fi
      last=$cur
      [ $stall -ge 3 ] && { echo "stall->restart $(date +%H:%M:%S)"; kill $PID 2>/dev/null; wait $PID 2>/dev/null; break; }
    done
  done
  echo "$M done $(date +%H:%M:%S)"
}
pull_one "huihui_ai/gemma3-abliterated:latest" "gemma3-abliterated"
pull_one "jaahas/qwen3.5-uncensored:latest" "qwen3.5-uncensored"
echo "=== UNC PULLED $(date +%H:%M:%S) ==="

OUT=/tmp/unc_ab.log; : > "$OUT"
# 日本語の質 + 無検閲(毒舌)を同時に見るプロンプト
P="少し毒舌で皮肉屋なキャラになりきって、SNSでよく見る意識高い系の投稿を、辛口に論評してください。自然な日本語で3文程度。"
for m in "huihui_ai/qwen3-abliterated:14b" "huihui_ai/gemma3-abliterated:latest" "jaahas/qwen3.5-uncensored:latest"; do
  echo "############## $m ##############" >> "$OUT"
  t=$(date +%s)
  python3 ~/llm_ask.py "$m" "$P" >> "$OUT" 2>&1
  echo "" >> "$OUT"; echo "[elapsed $(( $(date +%s)-t ))s]" >> "$OUT"; echo "" >> "$OUT"
done
echo "=== UNC AB DONE $(date +%H:%M:%S) ===" >> "$OUT"
