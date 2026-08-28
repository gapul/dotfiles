#!/bin/bash
# macmini ローカルAIスタック bootstrap(まっさら or 再構築用)
# 前提: darwin-rebuild 済(brew: ffmpeg/aria2/socat/container、nix: uv、SSH/sleep設定)
# 使い方: bash configs/macmini/bootstrap.sh [--models] [--venvs] [--scripts] [--services]
#         引数なし = 全部
set -u
eval "$(/opt/homebrew/bin/brew shellenv)"
H="$HOME"
# uv は nix (Home Manager profile) 管理。brew shellenv の後に置いて nix を優先させる。
export PATH="$H/.local/state/nix/profile/bin:$PATH"
UV=uv
say(){ echo -e "\n=== $* ==="; }

do_all=1; [ "$#" -gt 0 ] && do_all=0
want(){ [ "$do_all" = 1 ] && return 0; case " $* " in *" $1 "*) return 0;; esac; return 1; }
has(){ printf '%s ' "$@" | grep -q " $FLAG "; }

# ---------- scripts: Home Manager 管理の配置を確認 ----------
if [ $do_all = 1 ] || printf '%s' "$*" | grep -q scripts; then
  say "スクリプト配置"
  [ -x "$H/.local/share/ai-stack/ai-stack.sh" ] || {
    echo "Home Manager未適用: 先に darwin-rebuild switch を実行してください" >&2
    exit 1
  }
  echo "  Home Manager管理のbin/servicesを確認"
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

# ---------- models: manifest から macmini直DL(hf-mirror/GitHub) ----------
if [ $do_all = 1 ] || printf '%s' "$*" | grep -q models; then
  say "モデル取得(母艦経由せず macmini直)"
  echo "  ※ 大物safetensors(whisper/vlm/sbv2/rag/separator)は hf-mirror.com から aria2 self-healingで取得。"
  echo "    詳細URLは models.txt 参照。HF_ENDPOINT=https://hf-mirror.com で huggingface_hub 経由も可だが"
  echo "    308リダイレクトを扱えない場合あり→ aria2で各ファイルをローカルに落とし HF_HUB_OFFLINE=1 で読込。"
fi

# ---------- services: コンテナランタイム + launchd起動 ----------
if [ $do_all = 1 ] || printf '%s' "$*" | grep -q services; then
  say "コンテナランタイム + launchd"
  container system status 2>/dev/null | grep -q running || container system start
  container system kernel set --recommended 2>/dev/null || true   # 初回のみ
  # loopback待受のホストサービスをコンテナから参照するためのApple Container公式機構。
  # macOS再起動でpf ruleが消えるため、bootstrap再実行または運用自動化が必要。
  sudo container system dns delete host.container.internal 2>/dev/null || true
  sudo container system dns create host.container.internal --localhost 203.0.113.113
  launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.ai-stack"
  echo "  ai-stack supervisor 起動(埋め込み/パネル/コンテナ/socat を冪等維持)"
fi

say "完了。Caddy(別ホスト)に chat/docs/tools ブロック追記でスマホ公開。"
