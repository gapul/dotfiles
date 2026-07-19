#!/bin/bash
cd ~/ComfyUI/models || exit 1
ARIA="/opt/homebrew/bin/aria2c -c -x16 -s16 -k1M --max-tries=0 --retry-wait=10 --file-allocation=none --console-log-level=warn --summary-interval=30"
log(){ echo "[$(date +%H:%M:%S)] $*"; }
log "START qwen-image-edit fetch"
until $ARIA --checksum=sha-256=08f27cdf3e760edef5136ab0afdb9d3ed7a2799bd730b8d5cd9ecb291d808425 -d diffusion_models -o Qwen-Image-Edit-2509-Q4_K_M.gguf "https://huggingface.co/QuantStack/Qwen-Image-Edit-2509-GGUF/resolve/main/Qwen-Image-Edit-2509-Q4_K_M.gguf"; do log "qwen-gguf retry"; sleep 15; done
log "Qwen-Edit GGUF VERIFIED"
until $ARIA --checksum=sha-256=cb5636d852a0ea6a9075ab1bef496c0db7aef13c02350571e388aea959c5c0b4 -d text_encoders -o qwen_2.5_vl_7b_fp8_scaled.safetensors "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors"; do log "qwen-te retry"; sleep 15; done
log "Qwen2.5-VL encoder VERIFIED"
until $ARIA --checksum=sha-256=a70580f0213e67967ee9c95f05bb400e8fb08307e017a924bf3441223e023d1f -d vae -o qwen_image_vae.safetensors "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/vae/qwen_image_vae.safetensors"; do log "qwen-vae retry"; sleep 15; done
log "qwen VAE VERIFIED"
log "QWEN ALL VERIFIED DONE"
