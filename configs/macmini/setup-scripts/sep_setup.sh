#!/bin/bash
eval "$(/opt/homebrew/bin/brew shellenv)"
export PATH="/opt/homebrew/bin:$PATH"
export PYTORCH_ENABLE_MPS_FALLBACK=1
CKPT="vocals_mel_band_roformer.ckpt"
URL="https://hf-mirror.com/KimberleyJSN/melbandroformer/resolve/main/MelBandRoformer.ckpt"
TARGET=913106900
D="$HOME/sep-models"
# hf-mirrorから自己修復DL(macmini直・母艦不使用)
until [ "$(stat -f%z "$D/$CKPT" 2>/dev/null || echo 0)" = "$TARGET" ]; do
  echo "dl $(date +%H:%M:%S): $(stat -f%z "$D/$CKPT" 2>/dev/null || echo 0)/$TARGET"
  aria2c -c -x8 -s8 -k1M --max-tries=0 --retry-wait=5 --lowest-speed-limit=50K \
    --file-allocation=none --console-log-level=warn -d "$D" -o "$CKPT" "$URL"
  sleep 3
done
echo "DL完了。zip検証:"
python3 -c "import zipfile,sys; sys.exit(0 if zipfile.is_zipfile(\"$D/$CKPT\") else 1)" && echo "ZIP OK" || { echo "CORRUPT→やり直し"; rm -f "$D/$CKPT"; exec bash ~/sep_setup.sh; }
~/sep-venv/bin/mlx-audio-separator --download_model_only -m "$CKPT" --model_file_dir "$D" 2>&1 | tail -1
echo "=== 分離実行 ==="
~/sep-venv/bin/mlx-audio-separator /tmp/mix.wav -m "$CKPT" --model_file_dir "$D" --output_dir /tmp/sepout --save_converted_safetensors 2>&1 | grep -iE "vocal|instrument|error|complet|saved|written|traceback|convert" | tail -8
echo "=== SEP DONE ==="
ls -lh /tmp/sepout/ | awk "{print \$5, \$9}"
