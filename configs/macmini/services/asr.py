"""Offline speech recognition with sherpa-onnx: silero VAD cuts the audio, then one model decodes each
segment.

    asr.py <16kHz mono wav> <output base> <parakeet|cohere> <lang> <txt|srt|vtt|json|all>

Writes <output base>.<fmt>. The json holds every segment with start/end seconds, which is what
diarize_cluster.py reads.

Models (configs/macmini/models.txt):
  parakeet  NeMo Parakeet TDT-CTC 0.6B ja, int8. Japanese only. The most accurate single model on a
            2-hour hall recording (2026-11), well ahead of Whisper large-v3, kotoba-whisper,
            ReazonSpeech and Apple SpeechTranscriber.
  cohere    Cohere Transcribe, 14 languages, int8. The most readable punctuation, but it silently
            drops some segments, so it is the fallback for non-Japanese audio and a second opinion.

The VAD settings come from the same comparison: the silero defaults (threshold 0.5) skip quiet
speakers in a hall, and segments longer than 15 s make both models drop the tail.
"""

import json
import sys
from pathlib import Path

import sherpa_onnx as so
import soundfile as sf

MODELS = Path.home() / ".local/share/models/asr"

wav, out_base, model, lang, fmt = sys.argv[1:6]

if model == "parakeet":
    d = MODELS / "parakeet-ja-int8"
    rec = so.OfflineRecognizer.from_nemo_ctc(
        model=str(d / "model.int8.onnx"), tokens=str(d / "tokens.txt"), num_threads=4
    )
elif model == "cohere":
    d = MODELS / "cohere-14lang-int8"
    rec = so.OfflineRecognizer.from_cohere_transcribe(
        encoder=str(d / "encoder.int8.onnx"),
        decoder=str(d / "decoder.int8.onnx"),
        tokens=str(d / "tokens.txt"),
        num_threads=6,
        language=lang,
    )
else:
    sys.exit(f"unknown model: {model}")

audio, sr = sf.read(wav, dtype="float32")
if audio.ndim != 1 or sr != 16000:
    sys.exit("input must be 16 kHz mono")

cfg = so.VadModelConfig()
cfg.silero_vad.model = str(MODELS / "silero_vad.onnx")
cfg.silero_vad.threshold = 0.25
cfg.silero_vad.min_silence_duration = 0.5
cfg.silero_vad.max_speech_duration = 15
cfg.sample_rate = sr
vad = so.VoiceActivityDetector(cfg, buffer_size_in_seconds=60)

segs = []


def drain() -> None:
    while not vad.empty():
        s = vad.front
        st = rec.create_stream()
        st.accept_waveform(sr, s.samples)
        rec.decode_stream(st)
        text = st.result.text.strip()
        if text:
            segs.append(
                {"start": s.start / sr, "end": (s.start + len(s.samples)) / sr, "text": text}
            )
        vad.pop()


w = cfg.silero_vad.window_size
for i in range(0, len(audio), w):
    vad.accept_waveform(audio[i : i + w])
    drain()
vad.flush()
drain()


def hms(t: float) -> str:
    t = int(t)
    return f"{t // 3600}:{t // 60 % 60:02d}:{t % 60:02d}"


def stamp(t: float, sep: str) -> str:
    ms = round(t * 1000)
    return f"{ms // 3600000:02d}:{ms // 60000 % 60:02d}:{ms // 1000 % 60:02d}{sep}{ms % 1000:03d}"


def cues(sep: str) -> str:
    return "".join(
        f"{i}\n{stamp(s['start'], sep)} --> {stamp(s['end'], sep)}\n{s['text']}\n\n"
        for i, s in enumerate(segs, 1)
    )


writers = {
    "txt": lambda: "".join(f"[{hms(s['start'])}] {s['text']}\n" for s in segs),
    "srt": lambda: cues(","),
    "vtt": lambda: "WEBVTT\n\n" + cues("."),
    "json": lambda: (
        json.dumps(
            {"model": model, "language": lang, "segments": segs}, ensure_ascii=False, indent=1
        )
        + "\n"
    ),
}
for f in writers if fmt == "all" else [fmt]:
    Path(f"{out_base}.{f}").write_text(writers[f]())
print(f"[{model}] {len(segs)} segments, {len(audio) / sr / 60:.1f} min", file=sys.stderr)
