#!/bin/bash
# macmini: klein 3ファイルを目標サイズまで自己修復ダウンロード (bash3.2互換)
set -u
export PATH="/opt/homebrew/bin:$PATH"
M="$HOME/ComfyUI/models"
BASE="https://huggingface.co/Comfy-Org/vae-text-encorder-for-flux-klein-4b/resolve/main/split_files"
mkdir -p "$M/diffusion_models" "$M/text_encoders" "$M/vae"

FILES=(
  "$M/diffusion_models/flux-2-klein-4b.safetensors"
  "$M/text_encoders/qwen_3_4b.safetensors"
  "$M/vae/flux2-vae.safetensors"
)
TARGETS=( 7751105712 8044982048 336211292 )

cat > /tmp/klein_urls.txt <<EOF
$BASE/diffusion_models/flux-2-klein-4b.safetensors
  dir=$M/diffusion_models
  out=flux-2-klein-4b.safetensors
$BASE/text_encoders/qwen_3_4b.safetensors
  dir=$M/text_encoders
  out=qwen_3_4b.safetensors
$BASE/vae/flux2-vae.safetensors
  dir=$M/vae
  out=flux2-vae.safetensors
EOF

sz(){ [ -f "$1" ] && stat -f%z "$1" || echo 0; }
done_all(){
  local i=0
  while [ $i -lt ${#FILES[@]} ]; do
    [ "$(sz "${FILES[$i]}")" -ge "${TARGETS[$i]}" ] || return 1
    i=$((i+1))
  done
  return 0
}

pass=0
until done_all; do
  pass=$((pass+1))
  echo "=== pass $pass $(date +%H:%M:%S) ==="
  i=0
  while [ $i -lt ${#FILES[@]} ]; do
    c=$(sz "${FILES[$i]}"); t=${TARGETS[$i]}
    echo "  $((c*100/t))%  $(basename "${FILES[$i]}")"
    i=$((i+1))
  done
  aria2c -c -j3 -x4 -s4 -k1M --max-tries=8 --retry-wait=10 \
    --lowest-speed-limit=0 --max-connection-per-server=4 \
    --file-allocation=none --summary-interval=30 --console-log-level=warn \
    -i /tmp/klein_urls.txt
  sleep 5
done
echo "=== KLEIN DOWNLOAD COMPLETE $(date +%H:%M:%S) ==="
i=0; while [ $i -lt ${#FILES[@]} ]; do echo "  $(sz "${FILES[$i]}")  $(basename "${FILES[$i]}")"; i=$((i+1)); done
