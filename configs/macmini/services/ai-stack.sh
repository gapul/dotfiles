#!/bin/bash
# macmini AIスタック 冪等スーパーバイザ(launchd RunAtLoad+KeepAlive)
eval "$(/opt/homebrew/bin/brew shellenv)"
export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:$HOME/.local/bin:$PATH"
export HF_HUB_OFFLINE=1 PYTORCH_ENABLE_MPS_FALLBACK=1 PYTHONPYCACHEPREFIX=$HOME/.cache/pycache
# launchd 配下は .zshenv を読まないため XDG 系はここでも明示 (matplotlib が ~/.matplotlib を再生成する対策)
export MPLCONFIGDIR=$HOME/.config/matplotlib
H=$HOME
# 安全な既定値は loopback。Tailscale 等へ公開する場合だけ launchd 環境で明示する。
AI_BIND_ADDR="${AI_BIND_ADDR:-127.0.0.1}"
up(){ curl -s --max-time 3 -o /dev/null "$1"; }

while true; do
  # Python系サービス
  up http://127.0.0.1:8900/health || (nohup "$H/.local/share/venvs/rag-venv/bin/python" -m uvicorn rag_server:app --host "$AI_BIND_ADDR" --port 8900 --app-dir "$H/.local/share/ai-stack" >/tmp/rag_server.log 2>&1 &)
  up http://127.0.0.1:8901/ || (nohup "$H/.local/share/venvs/rag-venv/bin/python" -m uvicorn ai_panel:app --host "$AI_BIND_ADDR" --port 8901 --app-dir "$H/.local/share/ai-stack" >/tmp/ai_panel.log 2>&1 &)
  sleep 30
done
