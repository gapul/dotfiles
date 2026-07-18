#!/bin/bash
# macmini AIスタック 冪等スーパーバイザ(launchd RunAtLoad+KeepAlive)
eval "$(/opt/homebrew/bin/brew shellenv)"
export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:$HOME/.local/bin:$PATH"
export HF_HUB_OFFLINE=1 PYTORCH_ENABLE_MPS_FALLBACK=1 PYTHONPYCACHEPREFIX=$HOME/.cache/pycache
# launchd 配下は .zshenv を読まないため XDG 系はここでも明示 (matplotlib が ~/.matplotlib を再生成する対策)
export MPLCONFIGDIR=$HOME/.config/matplotlib
H=/Users/gapul
up(){ curl -s --max-time 3 -o /dev/null "$1"; }

start_owui(){ container run -d --name open-webui --dns 1.1.1.1 -e OLLAMA_BASE_URL=http://192.168.116.91:11434 -e WEBUI_AUTH=False -e RAG_EMBEDDING_ENGINE=ollama -e HF_HUB_OFFLINE=1 -v $H/ai/data/openwebui:/app/backend/data ghcr.io/open-webui/open-webui:main >/dev/null 2>&1; }
start_allm(){ container run -d --name anythingllm --dns 1.1.1.1 -e STORAGE_DIR=/app/server/storage \
  -e LLM_PROVIDER=ollama -e OLLAMA_BASE_PATH=http://192.168.116.91:11434 -e OLLAMA_MODEL_PREF=gemma4:12b-it-qat -e OLLAMA_MODEL_TOKEN_LIMIT=8192 \
  -e EMBEDDING_ENGINE=generic-openai -e EMBEDDING_BASE_PATH=http://192.168.116.91:8900/v1 -e EMBEDDING_MODEL_PREF=ruri-v3-310m -e GENERIC_OPEN_AI_EMBEDDING_API_KEY=sk-none -e EMBEDDING_MODEL_MAX_CHUNK_LENGTH=512 \
  -e VECTOR_DB=lancedb \
  -v $H/ai/data/anythingllm:/app/server/storage docker.io/mintplexlabs/anythingllm:latest >/dev/null 2>&1; }
start_mc(){ container run -d --name mc-server --memory 5g --dns 1.1.1.1 -e EULA=TRUE -e TYPE=PAPER -e VERSION=LATEST -e MEMORY=4G -e ONLINE_MODE=TRUE -p 25565:25565 -v $H/ai/data/mc:/data docker.io/itzg/minecraft-server:latest >/dev/null 2>&1; }

ensure_container(){ # name start_func
  container list 2>/dev/null | awk -v n="$1" "\$1==n{print \$5}" | grep -q running && return
  container start "$1" >/dev/null 2>&1 || { container rm -f "$1" >/dev/null 2>&1; "$2"; }
}

while true; do
  # Python系サービス
  pgrep -f "ollama serve" >/dev/null || (export OLLAMA_HOST=0.0.0.0:11434 OLLAMA_KEEP_ALIVE=30m; nohup ollama serve >/tmp/ollama.log 2>&1 &)
  up http://127.0.0.1:8900/health || (nohup $H/ai/venvs/rag-venv/bin/python -m uvicorn rag_server:app --host 0.0.0.0 --port 8900 --app-dir $H/ai/bin >/tmp/rag_server.log 2>&1 &)
  up http://127.0.0.1:8901/ || (nohup $H/ai/venvs/rag-venv/bin/python -m uvicorn ai_panel:app --host 0.0.0.0 --port 8901 --app-dir $H/ai/bin >/tmp/ai_panel.log 2>&1 &)
  # コンテナランタイム+各コンテナ
  container system status 2>/dev/null | grep -q running || container system start >/dev/null 2>&1
  ensure_container open-webui start_owui
  ensure_container anythingllm start_allm
  ensure_container mc-server start_mc
  # socat 転送 (container 1.1.0 の -p は listener だけ立って転送しない罠があるため socat 継続)
  if ! { up http://127.0.0.1:3001/ && up http://127.0.0.1:3000/; }; then
    $H/ai/bin/container_proxy.sh >/dev/null 2>&1
  fi
  # vmnet 劣化検知は container IP への ping で行う。HTTP 判定はアプリ起動中も
  # 落ちる=起動待ちと劣化を区別できず、5分毎の再起動ループを起こした (2026-07-18)
  dead=""
  for nm in open-webui anythingllm; do
    cip=$(container list 2>/dev/null | awk -v n="$nm" "\$1==n{print \$6}" | cut -d/ -f1)
    [ -n "$cip" ] && ! ping -c1 -t2 "$cip" >/dev/null 2>&1 && dead="$dead $nm($cip)"
  done
  if [ -n "$dead" ]; then
    now=$(date +%s); last=$(cat /tmp/vmnet_recover_ts 2>/dev/null || echo 0)
    if [ $((now - last)) -gt 600 ]; then
      echo "$now" > /tmp/vmnet_recover_ts
      echo "[$(date +%H:%M:%S)] vmnet劣化検知($dead)→system stop/start"
      # stop だけでは vmnet NAT デーモンの腐りが残る (2026-07-18 実証) ので明示 kill
      container system stop >/dev/null 2>&1; sleep 3
      pkill -f "com.apple.container" 2>/dev/null; sleep 3
      container system start >/dev/null 2>&1; sleep 5
      $H/ai/bin/container_proxy.sh >/dev/null 2>&1
    fi
  fi
  sleep 30
done
