#!/bin/bash
export PATH="/run/current-system/sw/bin:$PATH"
export OLLAMA_HOST=127.0.0.1:11434
for m in "huihui_ai/qwen3-abliterated:14b" "gemma4:12b-it-qat" "qwen3-coder:30b-a3b-q4_K_M"; do
  echo "=== pulling $m $(date +%H:%M:%S) ==="
  for try in 1 2 3 4 5; do ollama pull "$m" && break; echo "retry $try"; sleep 10; done
done
echo "=== ALL LLMS PULLED $(date +%H:%M:%S) ==="
ollama list
