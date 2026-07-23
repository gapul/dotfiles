#!/bin/bash
eval "$(/opt/homebrew/bin/brew shellenv)"
IMG="ghcr.io/open-webui/open-webui:main"
until container image list 2>/dev/null | grep -q "open-webui"; do
  echo "=== OpenWebUI pull $(date +%H:%M:%S) ==="
  container image pull "$IMG" 2>&1 | tail -2; sleep 8
done
echo "=== OPENWEBUI IMAGE READY $(date +%H:%M:%S) ==="
container rm -f open-webui 2>/dev/null
mkdir -p "$HOME/openwebui-data"
container run -d --name open-webui --dns 1.1.1.1 \
  -e OLLAMA_BASE_URL=http://host.container.internal:11434 -e WEBUI_AUTH=True -e ENABLE_IMAGE_GENERATION=True -e IMAGE_GENERATION_ENGINE=comfyui -e COMFYUI_BASE_URL=http://host.container.internal:8188 -e IMAGE_GENERATION_MODEL=RealVisXL_V5.0_fp16.safetensors -e IMAGE_SIZE=832x1216 -e IMAGE_STEPS=22 -e RAG_EMBEDDING_ENGINE=ollama -e HF_HUB_OFFLINE=1 \
  -v "$HOME/openwebui-data:/app/backend/data" -v "$HOME/openwebui-hf-cache:/root/.cache/huggingface" "$IMG" 2>&1 | tail -1
sleep 25
~/container_proxy.sh
echo "=== OPENWEBUI STARTED $(date +%H:%M:%S) ==="
