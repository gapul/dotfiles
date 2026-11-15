"""Speaker labels for an asr.py transcript: one wespeaker embedding per VAD segment, then
agglomerative clustering on cosine distance.

    diarize_cluster.py <16kHz mono wav> <asr.py json> <output .diarized.txt> [threshold]

This replaced the pyannote speaker-diarization-3.1 pipeline (2026-11). On a 2-hour hall recording the
pipeline left about half of the recognized speech without a speaker turn, while clustering the
segments the recognizer already found labels every line. 0.7 split the speakers of that recording
correctly; lower it if two voices merge, raise it if one voice splits.
"""

import json
import sys
import warnings
from collections import Counter
from pathlib import Path

import numpy as np
import soundfile as sf
import torch

# pyannote warns at import that torchcodec cannot load FFmpeg. Audio is passed in memory, so it is not used.
warnings.filterwarnings("ignore", message=r"\s*torchcodec is not installed correctly")
from pyannote.audio import Inference, Model  # noqa: E402
from sklearn.cluster import AgglomerativeClustering  # noqa: E402

wav, asr_json, out = sys.argv[1:4]
thr = float(sys.argv[4]) if len(sys.argv) > 4 else 0.7

audio, sr = sf.read(wav, dtype="float32")
segs = json.loads(Path(asr_json).read_text())["segments"]
if not segs:
    sys.exit("no speech")

dev = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
inf = Inference(
    Model.from_pretrained("pyannote/wespeaker-voxceleb-resnet34-LM"), window="whole", device=dev
)
embs = []
for s in segs:
    # Embeddings of very short segments are noise; pad them to 1.5 s of context.
    a = int(s["start"] * sr)
    b = max(int(s["end"] * sr), a + int(1.5 * sr))
    embs.append(inf({"waveform": torch.from_numpy(audio[a:b]).unsqueeze(0), "sample_rate": sr}))
emb = np.stack(embs)
emb /= np.linalg.norm(emb, axis=1, keepdims=True)
if len(segs) > 1:
    lab = AgglomerativeClustering(
        n_clusters=None, distance_threshold=thr, metric="cosine", linkage="average"
    ).fit_predict(emb)
else:
    lab = [0]

# Name speakers A, B, ... by amount of speech, so the main speaker is A.
order = [c for c, _ in Counter(lab).most_common()]
name = {c: "話者" + (chr(ord("A") + i) if i < 26 else str(i + 1)) for i, c in enumerate(order)}


def hms(t: float) -> str:
    t = int(t)
    return f"{t // 3600}:{t // 60 % 60:02d}:{t % 60:02d}"


lines, cur = [], None
for s, c in zip(segs, lab):
    if name[c] != cur:
        cur = name[c]
        lines.append(f"\n[{hms(s['start'])}] {cur}:")
    lines.append(s["text"])
Path(out).write_text("\n".join(lines).lstrip("\n") + "\n")
print(f"[speakers: {len(order)}]", file=sys.stderr)
