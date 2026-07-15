import sys, os, json, torch
from pyannote.audio import Pipeline

wav = sys.argv[1]; whisper_json = sys.argv[2]
token = os.environ.get("HF_TOKEN")

data = json.load(open(whisper_json))
segs = [{"start": s["start"], "end": s["end"], "text": s["text"].strip()}
        for s in data.get("segments", []) if s.get("text", "").strip()]

try:
    pipe = Pipeline.from_pretrained("pyannote/speaker-diarization-3.1", token=token)
except TypeError:
    pipe = Pipeline.from_pretrained("pyannote/speaker-diarization-3.1", use_auth_token=token)

dev = "mps" if torch.backends.mps.is_available() else "cpu"
try:
    pipe.to(torch.device(dev))
except Exception:
    dev = "cpu"
print("[diarization on " + dev + "]", file=sys.stderr)

out = pipe(wav)
dia = getattr(out, "speaker_diarization", out)  # pyannote 4.x compat
turns = [(t.start, t.end, spk) for t, _, spk in dia.itertracks(yield_label=True)]

def speaker_of(a, b):
    best, bov = None, 0.0
    for ts, te, spk in turns:
        ov = max(0.0, min(b, te) - max(a, ts))
        if ov > bov: bov, best = ov, spk
    return best

order, label = [], {}
def jp(spk):
    if spk is None: return "話者?"
    if spk not in label:
        label[spk] = "話者" + chr(ord("A") + len(order)); order.append(spk)
    return label[spk]

lines, cur, buf = [], None, []
for s in segs:
    who = jp(speaker_of(s["start"], s["end"]))
    if who != cur:
        if buf: lines.append(cur + ": " + " ".join(buf))
        cur, buf = who, [s["text"]]
    else:
        buf.append(s["text"])
if buf: lines.append(cur + ": " + " ".join(buf))

result = "\n".join(lines)
print(result)
base = os.path.splitext(whisper_json)[0]
open(base + ".diarized.txt", "w").write(result + "\n")
print("[speakers: " + str(len(order)) + "]", file=sys.stderr)
