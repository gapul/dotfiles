#!/bin/bash
set -u
export PATH="/opt/homebrew/bin:$PATH"
VENV=/Users/gapul/gsv-venv
DL=/Users/gapul/gsv-dl
echo "[nltk] extract -> $VENV/nltk_data"
unzip -q -o "$DL/nltk_data.zip" -d "$VENV"
echo "[openjtalk] extract -> pyopenjtalk module dir"
PJ=$("$VENV/bin/python" -c "import os,pyopenjtalk; print(os.path.dirname(pyopenjtalk.__file__))")
tar -xzf "$DL/open_jtalk_dic.tar.gz" -C "$PJ"
echo "[verify] pretrained models present:"
ls /Users/gapul/GPT-SoVITS/GPT_SoVITS/pretrained_models 2>/dev/null | head
echo "=== GSV FINALIZE DONE ==="
