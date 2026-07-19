#!/bin/bash
set -u
export PATH="/opt/homebrew/bin:$PATH"
M="$HOME/sbv2-models"
DB="$M/deberta-v2-large-japanese-char-wwm"
JV="$M/jvnv-F1-jp"
mkdir -p "$DB" "$JV"
BB="https://huggingface.co/ku-nlp/deberta-v2-large-japanese-char-wwm/resolve/main"
JB="https://huggingface.co/litagin/style_bert_vits2_jvnv/resolve/main/jvnv-F1-jp"
cat > /tmp/sbv2_urls.txt <<EOF
$BB/model.safetensors
  dir=$DB
  out=model.safetensors
$BB/config.json
  dir=$DB
  out=config.json
$BB/special_tokens_map.json
  dir=$DB
  out=special_tokens_map.json
$BB/tokenizer_config.json
  dir=$DB
  out=tokenizer_config.json
$BB/vocab.txt
  dir=$DB
  out=vocab.txt
$JB/config.json
  dir=$JV
  out=config.json
$JB/jvnv-F1-jp_e160_s14000.safetensors
  dir=$JV
  out=jvnv-F1-jp_e160_s14000.safetensors
$JB/style_vectors.npy
  dir=$JV
  out=style_vectors.npy
EOF
n=0
while true; do
  n=$((n+1)); echo "=== pass $n $(date +%H:%M:%S) ==="
  aria2c -c -j4 -x8 -s8 -k1M --max-tries=10 --retry-wait=8 \
    --lowest-speed-limit=0 --max-connection-per-server=8 \
    --file-allocation=none --console-log-level=warn --summary-interval=30 \
    -i /tmp/sbv2_urls.txt
  [ $? -eq 0 ] && { echo "=== SBV2 MODELS COMPLETE $(date +%H:%M:%S) ==="; break; }
  sleep 5
done
