#!/bin/bash
cd ~/ComfyUI/models || exit 1
ARIA="/opt/homebrew/bin/aria2c -c -x16 -s16 -k1M --max-tries=0 --retry-wait=10 --file-allocation=none --console-log-level=warn --summary-interval=30"
TOKEN=$(tr -d "\r\n" < ~/.civitai_token 2>/dev/null)
RV=6a35a7855770ae9820a3c931d4964c3817b6d9e3c6f9c4dabb5b3a94e5643b80
CN=9fae2e50cb431bfcbe05822b59ec2228df545ef27f711dea8949e9f4ed9f7cdc
PONY=67ab2fd8ec439a89b3fedb15cc65f54336af163c7eb5e4f2acc98f090a29b0b3
log(){ echo "[$(date +%H:%M:%S)] $*"; }
log "START checksum-verified fetch"
until $ARIA --checksum=sha-256=$RV -d checkpoints -o RealVisXL_V5.0_fp16.safetensors "https://huggingface.co/SG161222/RealVisXL_V5.0/resolve/main/RealVisXL_V5.0_fp16.safetensors"; do log "RealVis retry"; sleep 15; done
log "RealVis VERIFIED"
until $ARIA --checksum=sha-256=$CN -d controlnet -o xinsir-controlnet-union-sdxl-promax.safetensors "https://huggingface.co/xinsir/controlnet-union-sdxl-1.0/resolve/main/diffusion_pytorch_model_promax.safetensors"; do log "CN retry"; sleep 15; done
log "ControlNet VERIFIED"
until $ARIA --checksum=sha-256=$PONY -d checkpoints -o ponyDiffusionV6XL_v6.safetensors "https://civitai.com/api/download/models/290640?token=$TOKEN"; do log "Pony retry"; sleep 15; done
log "Pony VERIFIED"
log "ALL VERIFIED DONE"
