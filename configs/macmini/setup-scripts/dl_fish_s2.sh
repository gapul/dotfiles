#!/bin/bash
# Fish Audio S2 Pro の 8bit MLX 変換 (6.3GB) を取る。fish-tts が読む。
# 本家 huggingface.co から素直に落ちた(実測 38-71MB/s)ので hf-mirror は経由しない。
set -u
export PATH="/opt/homebrew/bin:$PATH"
M="$HOME/.local/share/models/mlx/fish-s2-pro-8bit"
B="https://huggingface.co/appautomaton/fishaudio-s2-pro-8bit-mlx/resolve/main"
mkdir -p "$M/codec-mlx"
: > /tmp/fish_urls.txt
for f in LICENSE.md README.md chat_template.jinja config.json model.safetensors \
         special_tokens_map.json tokenizer.json tokenizer_config.json; do
  printf '%s/%s\n  dir=%s\n  out=%s\n' "$B" "$f" "$M" "$f" >> /tmp/fish_urls.txt
done
for f in config.json model.safetensors; do
  printf '%s/codec-mlx/%s\n  dir=%s/codec-mlx\n  out=%s\n' "$B" "$f" "$M" "$f" >> /tmp/fish_urls.txt
done
n=0
while true; do
  n=$((n+1)); echo "=== pass $n $(date +%H:%M:%S) ==="
  aria2c -c -j4 -x8 -s8 -k1M --max-tries=10 --retry-wait=8 \
    --file-allocation=none --console-log-level=warn --summary-interval=30 \
    -i /tmp/fish_urls.txt
  [ $? -eq 0 ] && { echo "=== FISH S2 PRO COMPLETE $(date +%H:%M:%S) ==="; break; }
  sleep 5
done
