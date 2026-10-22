#!/bin/bash
# macmini ローカルAIスタック bootstrap(まっさら or 再構築用)
# 前提: darwin-rebuild 済(nix: uv、SSH/sleep設定)
# 使い方: bash configs/macmini/bootstrap.sh [--venvs]   (引数なしでも同じ。venv の再構築だけを行う)
#   スクリプト配置と launchd (ai-stack) は Home Manager の宣言 (nix/home/macmini.nix、
#   RunAtLoad + KeepAlive) で済むので、ここでは扱わない。モデル取得は models.txt を参照して手で行う。
set -u
eval "$(/opt/homebrew/bin/brew shellenv)"
H="$HOME"
# uv は nix (Home Manager profile) 管理。brew shellenv の後に置いて nix を優先させる。
export PATH="$H/.local/state/nix/profile/bin:$PATH"
UV=uv
say(){ echo -e "\n=== $* ==="; }

# ---------- venvs: uv で再構築(ML依存のピン留めは実戦の教訓) ----------
case " $* " in
  "  " | *" --venvs "*) ;;
  *)
    echo "usage: bash configs/macmini/bootstrap.sh [--venvs]" >&2
    exit 2
    ;;
esac

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
# 表現力TTS/声クローン(Fish Audio S2 Pro, 純MLXなので torch は要らない。3.13以上)
$UV venv --python 3.13 "$H/.local/share/venvs/fish-venv"
$UV pip install --python "$H/.local/share/venvs/fish-venv/bin/python" mlx-speech
# 音声分離
$UV venv --python 3.12 "$H/sep-venv"
$UV pip install --python "$H/sep-venv/bin/python" mlx-audio-separator torch

# 声クローン(GPT-SoVITS本体は git clone 別途)
[ -d "$H/GPT-SoVITS" ] || git clone --depth 1 https://github.com/RVC-Boss/GPT-SoVITS.git "$H/GPT-SoVITS"
$UV venv --python 3.10 "$H/gsv-venv"
$UV pip install --python "$H/gsv-venv/bin/python" -r "$H/GPT-SoVITS/requirements.txt" torchcodec
echo "  venv一式 完了"

say "完了。Caddy(別ホスト)に chat/docs/tools ブロック追記でスマホ公開。"
