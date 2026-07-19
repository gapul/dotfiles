#!/bin/bash
cd ~/ComfyUI/models || exit 1
ARIA="/opt/homebrew/bin/aria2c -c -x16 -s16 -k1M --max-tries=0 --retry-wait=10 --file-allocation=none --console-log-level=warn --summary-interval=30"
log(){ echo "[$(date +%H:%M:%S)] $*"; }
log "START chroma fetch"
until $ARIA --checksum=sha-256=8c8d66177bfc584573dd21584399ebc1f00bde60acbbc48ac3cc8f58f10c6094 -d diffusion_models -o Chroma1-HD-Q8_0.gguf "https://huggingface.co/silveroxides/Chroma1-HD-GGUF/resolve/main/Chroma1-HD-Q8_0.gguf"; do log "Chroma retry"; sleep 15; done
log "Chroma VERIFIED"
until $ARIA --checksum=sha-256=7d330da4816157540d6bb7838bf63a0f02f573fc48ca4d8de34bb0cbfd514f09 -d text_encoders -o t5xxl_fp8_e4m3fn.safetensors "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors"; do log "t5 retry"; sleep 15; done
log "t5xxl VERIFIED"
until $ARIA --checksum=sha-256=afc8e28272cd15db3919bacdb6918ce9c1ed22e96cb12c4d5ed0fba823529e38 -d vae -o flux-ae.safetensors "https://huggingface.co/Comfy-Org/Lumina_Image_2.0_Repackaged/resolve/main/split_files/vae/ae.safetensors"; do log "ae retry"; sleep 15; done
log "flux-ae VERIFIED"
log "CHROMA ALL VERIFIED DONE"
