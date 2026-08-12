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

# マイクラ。VERSION は固定する。LATEST だと再起動のたびに本体が上がって、遊ぶ日に
# 全員がクライアントを合わせるまで入れなくなる。ヒープ 2G / view 8 / sim 5 は7人想定。
# ENABLE_AUTOPAUSE は使えない: knockd が eth0 に attach できず (CAP_NET_RAW と
# CAP_NET_ADMIN を足しても不可)、無人でも凍らない。止めたいときは container stop。
start_mc(){ container run -d --name mc-server --cpus 4 --memory 3g --dns 1.1.1.1 \
  -e EULA=TRUE -e TYPE=PAPER -e VERSION=26.1.2 -e MEMORY=2G -e USE_AIKAR_FLAGS=TRUE \
  -e ONLINE_MODE=TRUE -e VIEW_DISTANCE=8 -e SIMULATION_DISTANCE=5 -e MAX_PLAYERS=8 \
  -p 25565:25565 -v "$H/.local/share/minecraft:/data" docker.io/itzg/minecraft-server:latest >/dev/null 2>&1; }

ensure_container(){ # name start_func
  container list 2>/dev/null | awk -v n="$1" "\$1==n{print \$5}" | grep -q running && return
  container start "$1" >/dev/null 2>&1 || { container rm -f "$1" >/dev/null 2>&1; "$2"; }
}

while true; do
  # Python系サービス
  pgrep -f "ollama serve" >/dev/null || (export OLLAMA_HOST="$AI_BIND_ADDR:11434" OLLAMA_KEEP_ALIVE=30m; nohup ollama serve >/tmp/ollama.log 2>&1 &)
  up http://127.0.0.1:8900/health || (nohup "$H/.local/share/venvs/rag-venv/bin/python" -m uvicorn rag_server:app --host "$AI_BIND_ADDR" --port 8900 --app-dir "$H/.local/share/ai-stack" >/tmp/rag_server.log 2>&1 &)
  up http://127.0.0.1:8901/ || (nohup "$H/.local/share/venvs/rag-venv/bin/python" -m uvicorn ai_panel:app --host "$AI_BIND_ADDR" --port 8901 --app-dir "$H/.local/share/ai-stack" >/tmp/ai_panel.log 2>&1 &)
  # コンテナランタイム+マインクラフト。Web フロント2本 (open-webui/anythingllm) は
  # homeserver へ移設したので、ここに残るのは -p が素直に通る TCP のマイクラだけ。
  # 併せて self-ssh 転送と vmnet 劣化検知も削除した (HTTP 転送専用の仕掛けだった)。
  container system status 2>/dev/null | grep -q running || container system start >/dev/null 2>&1
  ensure_container mc-server start_mc
  sleep 30
done
