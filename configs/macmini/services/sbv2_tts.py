import sys, os
from pathlib import Path
import torch, soundfile as sf
from style_bert_vits2.nlp import bert_models
from style_bert_vits2.constants import Languages
from style_bert_vits2.tts_model import TTSModel

text = sys.argv[1]
out  = sys.argv[2] if len(sys.argv) > 2 else "out.wav"
style = sys.argv[3] if len(sys.argv) > 3 else "Neutral"

M = os.path.expanduser("~/ai/models/mlx/sbv2")
DB = os.path.join(M, "deberta-v2-large-japanese-char-wwm")
JV = os.path.join(M, "jvnv-F1-jp")

bm = bert_models.load_model(Languages.JP, DB)
bm.float()  # BERTがfp16でロードされ net_g(fp32)と不整合になるため float32 に統一
bert_models.load_tokenizer(Languages.JP, DB)

model = TTSModel(
    model_path=Path(JV) / "jvnv-F1-jp_e160_s14000.safetensors",
    config_path=Path(JV) / "config.json",
    style_vec_path=Path(JV) / "style_vectors.npy",
    device="cpu",
)
sr, audio = model.infer(text=text, style=style)
sf.write(out, audio, sr)
print(f"[wrote {out} sr={sr} style={style}]", file=sys.stderr)
