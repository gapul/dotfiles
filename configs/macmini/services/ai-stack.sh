#!/bin/bash
# macmini AIスタック 冪等スーパーバイザ(launchd RunAtLoad+KeepAlive)
eval "$(/opt/homebrew/bin/brew shellenv)"
export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:$HOME/.local/bin:$PATH"
export HF_HUB_OFFLINE=1 PYTORCH_ENABLE_MPS_FALLBACK=1
H=/Users/gapul
up(){ curl -s --max-time 3 -o /dev/null "$1"; }

start_owui(){ container run -d --name open-webui --dns 1.1.1.1 -e OLLAMA_BASE_URL=http://192.168.116.91:11434 -e WEBUI_AUTH=False -e RAG_EMBEDDING_ENGINE=ollama -e HF_HUB_OFFLINE=1 -v $H/openwebui-data:/app/backend/data ghcr.io/open-webui/open-webui:main >/dev/null 2>&1; }
start_allm(){ container run -d --name anythingllm --dns 1.1.1.1 -e STORAGE_DIR=/app/server/storage \
  -e LLM_PROVIDER=ollama -e OLLAMA_BASE_PATH=http://192.168.116.91:11434 -e OLLAMA_MODEL_PREF=gemma4:12b-it-qat -e OLLAMA_MODEL_TOKEN_LIMIT=8192 \
  -e EMBEDDING_ENGINE=generic-openai -e EMBEDDING_BASE_PATH=http://192.168.116.91:8900/v1 -e EMBEDDING_MODEL_PREF=ruri-v3-310m -e GENERIC_OPEN_AI_EMBEDDING_API_KEY=sk-none -e EMBEDDING_MODEL_MAX_CHUNK_LENGTH=512 \
  -e VECTOR_DB=lancedb \
  -v $H/anythingllm-data:/app/server/storage docker.io/mintplexlabs/anythingllm:latest >/dev/null 2>&1; }
start_mc(){ container run -d --name mc-server --memory 5g --dns 1.1.1.1 -e EULA=TRUE -e TYPE=PAPER -e VERSION=LATEST -e MEMORY=4G -e ONLINE_MODE=TRUE -p 25565:25565 -v $H/mc-data:/data docker.io/itzg/minecraft-server:latest >/dev/null 2>&1; }

ensure_container(){ # name start_func
  container list 2>/dev/null | awk -v n="$1" "\$1==n{print \$5}" | grep -q running && return
  container start "$1" >/dev/null 2>&1 || { container rm -f "$1" >/dev/null 2>&1; "$2"; }
}

while true; do
  # Python系サービス
  pgrep -f "ollama serve" >/dev/null || (export OLLAMA_HOST=0.0.0.0:11434 OLLAMA_KEEP_ALIVE=30m; nohup ollama serve >/tmp/ollama.log 2>&1 &)
  up http://127.0.0.1:8900/health || (nohup $H/rag-venv/bin/python -m uvicorn rag_server:app --host 0.0.0.0 --port 8900 --app-dir $H >/tmp/rag_server.log 2>&1 &)
  up http://127.0.0.1:8901/ || (nohup $H/rag-venv/bin/python -m uvicorn ai_panel:app --host 0.0.0.0 --port 8901 --app-dir $H >/tmp/ai_panel.log 2>&1 &)
  # コンテナランタイム+各コンテナ
  container system status 2>/dev/null | grep -q running || container system start >/dev/null 2>&1
  ensure_container open-webui start_owui
  ensure_container anythingllm start_allm
  ensure_container mc-server start_mc
  # socat転送(host:3000/3001が死んでたら張り直し)
  { up http://127.0.0.1:3001/ && up http://127.0.0.1:3000/; } || $H/container_proxy.sh >/dev/null 2>&1
  sleep 30
done
