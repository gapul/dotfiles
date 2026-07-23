#!/bin/bash
set -u
export PATH="/opt/homebrew/bin:$PATH"
BASE="https://huggingface.co/XXXXRT/GPT-SoVITS-Pretrained/resolve/main"
mkdir -p "$HOME/gsv-dl"
cat > /tmp/gsv_urls.txt <<EOF
$BASE/pretrained_models.zip
  dir="$HOME/gsv-dl"
  out=pretrained_models.zip
$BASE/nltk_data.zip
  dir="$HOME/gsv-dl"
  out=nltk_data.zip
$BASE/open_jtalk_dic_utf_8-1.11.tar.gz
  dir="$HOME/gsv-dl"
  out=open_jtalk_dic.tar.gz
EOF
n=0
while true; do
  n=$((n+1)); echo "=== pass $n $(date +%H:%M:%S) ==="
  aria2c -c -j3 -x8 -s8 -k1M --max-tries=10 --retry-wait=8 \
    --lowest-speed-limit=0 --max-connection-per-server=8 \
    --file-allocation=none --console-log-level=warn --summary-interval=30 \
    -i /tmp/gsv_urls.txt
  [ $? -eq 0 ] && break
  sleep 5
done
echo "=== extracting pretrained -> GPT_SoVITS/ ==="
unzip -q -o "$HOME/gsv-dl/pretrained_models.zip" -d "$HOME/GPT-SoVITS/GPT_SoVITS"
echo "=== GSV MODELS DOWNLOADED $(date +%H:%M:%S) ==="
