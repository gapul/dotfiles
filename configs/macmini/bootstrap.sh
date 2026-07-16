#!/bin/bash
# macmini ローカルAIスタック bootstrap(まっさら or 再構築用)
# 前提: darwin-rebuild 済(brew: ffmpeg/uv/aria2/socat/container、Ollama、SSH/sleep設定)
# 使い方: bash configs/macmini/bootstrap.sh [--models] [--venvs] [--scripts] [--services]
#         引数なし = 全部
set -u
eval "$(/opt/homebrew/bin/brew shellenv)"
DOT="$(cd "$(dirname "$0")" && pwd)"          # configs/macmini の絶対パス
H="$HOME"
UV=/opt/homebrew/bin/uv
say(){ echo -e "\n=== $* ==="; }

do_all=1; [ "$#" -gt 0 ] && do_all=0
want(){ [ "$do_all" = 1 ] && return 0; case " $* " in *" $1 "*) return 0;; esac; return 1; }
has(){ printf '%s ' "$@" | grep -q " $FLAG "; }

# ---------- scripts: dotfiles -> 実配置(out-of-store symlink) ----------
if [ $do_all = 1 ] || printf '%s' "$*" | grep -q scripts; then
  say "スクリプト配置"
  mkdir -p "$H/.local/bin"
  for f in "$DOT"/bin/*; do ln -sf "$f" "$H/.local/bin/$(basename "$f")"; done
  for f in "$DOT"/services/*; do ln -sf "$f" "$H/$(basename "$f")"; done
  mkdir -p "$H/Library/LaunchAgents"
  cp "$DOT/launchd/net.gapul.ai-stack.plist" "$H/Library/LaunchAgents/"
  echo "  bin/ -> ~/.local/bin, services/ -> ~/, plist設置"
fi

# ---------- venvs: uv で再構築(ML依存のピン留めは実戦の教訓) ----------
if [ $do_all = 1 ] || printf '%s' "$*" | grep -q venvs; then
  say "venv再構築(uv)"
  $UV tool install mlx-whisper
  $UV tool install mlx-vlm
  # RAG(埋め込み+リランク+サーバー+パネル)
  $UV venv --python 3.12 "$H/rag-venv"
  $UV pip install --python "$H/rag-venv/bin/python" sentence-transformers torch sentencepiece fastapi "uvicorn[standard]" python-multipart
  # 話者分離(pyannote 4.x, HF_TOKEN要)
  $UV venv --python 3.12 "$H/diarize-venv"
  $UV pip install --python "$H/diarize-venv/bin/python" "pyannote.audio>=3.3" torch torchaudio soundfile
  # TTS(Style-Bert-VITS2, numpy/setuptoolsピン重要)
  $UV venv --python 3.12 "$H/sbv2-venv"
  $UV pip install --python "$H/sbv2-venv/bin/python" style-bert-vits2 torch torchaudio soundfile "setuptools<81" "numpy==1.26.4"
  # 音声分離
  $UV venv --python 3.12 "$H/sep-venv"
  $UV pip install --python "$H/sep-venv/bin/python" mlx-audio-separator torch
  # 声クローン(GPT-SoVITS本体は git clone 別途)
  [ -d "$H/GPT-SoVITS" ] || git clone --depth 1 https://github.com/RVC-Boss/GPT-SoVITS.git "$H/GPT-SoVITS"
  $UV venv --python 3.10 "$H/gsv-venv"
  $UV pip install --python "$H/gsv-venv/bin/python" -r "$H/GPT-SoVITS/requirements.txt" torchcodec
  echo "  venv一式 完了"
fi

# ---------- models: manifest から macmini直DL(hf-mirror/GitHub/ollama) ----------
if [ $do_all = 1 ] || printf '%s' "$*" | grep -q models; then
  say "モデル取得(母艦経由せず macmini直)"
  # ollama系(登録速い)
  export OLLAMA_HOST=0.0.0.0:11434
  ollama pull gemma4:12b-it-qat &
  ollama pull qwen2.5-coder:14b &
  ollama pull jaahas/qwen3.5-uncensored:latest &
  wait
  echo "  ※ 大物safetensors(whisper/vlm/sbv2/rag/separator)は hf-mirror.com から aria2 self-healingで取得。"
  echo "    詳細URLは models.txt 参照。HF_ENDPOINT=https://hf-mirror.com で huggingface_hub 経由も可だが"
  echo "    308リダイレクトを扱えない場合あり→ aria2で各ファイルをローカルに落とし HF_HUB_OFFLINE=1 で読込。"
fi

# ---------- services: コンテナランタイム + launchd起動 ----------
if [ $do_all = 1 ] || printf '%s' "$*" | grep -q services; then
  say "コンテナランタイム + launchd"
  container system status 2>/dev/null | grep -q running || container system start
  container system kernel set --recommended 2>/dev/null || true   # 初回のみ
  launchctl bootout gui/501/net.gapul.ai-stack 2>/dev/null || true
  launchctl bootstrap gui/501 "$H/Library/LaunchAgents/net.gapul.ai-stack.plist"
  echo "  ai-stack supervisor 起動(ollama/埋め込み/パネル/コンテナ/socat を冪等維持)"
fi

say "完了。Caddy(別ホスト)に chat/docs/tools ブロック追記でスマホ公開。"
