#!/bin/bash
export PATH="/run/current-system/sw/bin:$PATH"
export OLLAMA_HOST=127.0.0.1:11434
# pull完了を待つ
while ! grep -q "ALL LLMS PULLED" /tmp/pull_llms.log 2>/dev/null; do sleep 30; done
sleep 5
OUT=/tmp/llm_ab.log
: > "$OUT"
PROMPT="次の内容を、丁寧な敬語で2〜3文の議事録にまとめてください。箇条書きにせず自然な文章で。内容: 来週の新機能リリースについて議論した。既知のバグが2件残っており、田中が金曜日までに修正する予定。"
for m in "gemma4:12b-it-qat" "huihui_ai/qwen3-abliterated:14b" "qwen3-coder:30b-a3b-q4_K_M"; do
  echo "############## $m ##############" >> "$OUT"
  START=$(date +%s)
  RESP=$(ollama run "$m" "$PROMPT" 2>/dev/null)
  END=$(date +%s)
  echo "$RESP" >> "$OUT"
  echo "" >> "$OUT"
  echo "[elapsed: $((END-START))s]" >> "$OUT"
  echo "" >> "$OUT"
done
echo "=== LLM FINALIZE DONE $(date +%H:%M:%S) ===" >> "$OUT"
echo "=== installed ===" >> "$OUT"
ollama list >> "$OUT" 2>&1
