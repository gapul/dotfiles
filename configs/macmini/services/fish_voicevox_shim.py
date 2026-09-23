#!/usr/bin/env python
"""VOICEVOX 互換シム: Fish S2 Pro (mlx-speech) を VOICEVOX エンジンのふりをさせる。

presenta の workers/video は `/audio_query` で読みのクエリを作り、それをそのまま `/synthesis` に
渡して WAV を受け取る、という 2 段の API しか使わない（workers/video/voicevox.ts）。
なのでクエリの中身は往復するだけでよく、ここでは原稿の文字列を入れて返している。

Fish は遅い（1 文字あたり 0.4 秒前後）。呼び出し側は 1 回の `/synthesis` を 120 秒しか待たないので
（voicevox.ts の timeoutMs 既定値）、持ち時間 --budget-seconds を超えそうなぶんは AivisSpeech に回す。
Fish が落ちているときも AivisSpeech に回す。どちらで喋ったかは必ずログに出す。

    fish-voicevox [--port 10202] [--budget-seconds 90]
"""

from __future__ import annotations

import argparse
import io
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import wave
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

import numpy as np

# VOICEVOX の話者 id に相当するもの。Fish は話者を選べない（声は reference audio で決まる）ので
# 1 つだけ載せて、presenta が何を指してきても同じ声で読む。
SPEAKER_ID = 900000001
SPEAKER_NAME = "Fish S2 Pro"

# 1 回の合成に渡す上限。presenta 側も 120 字で切っているが、上限より長い 1 文はそのまま来る
# （lib/video.ts の splitNarration）。長すぎる原稿は生成が詰まるので、ここでも句点で切って順に読ませ、
# 1 本の WAV に繋いで返す。
MAX_CHARS = 120

TARGET_PEAK = 10 ** (-1.0 / 20)  # -1 dBFS。Fish の出力は素のままだと -11dBFS 前後で小さい。

# Fish の生成速度の見積り（秒/文字）。1 かたまり合成するたびに実測で上書きする。
# 初期値は 102 字 -> 42.1 秒の実測から。
INITIAL_SECONDS_PER_CHAR = 0.41


def split_text(text: str, max_chars: int = MAX_CHARS) -> list[str]:
    """句点の後ろで切って、上限に収まるところまで繋ぎ直す。上限より長い 1 文はそのまま返す。"""
    pieces = [p.strip() for p in re.split(r"(?<=[。！？!?])", text) if p.strip()]
    if not pieces:
        return []
    chunks: list[str] = []
    for piece in pieces:
        if chunks and len(chunks[-1]) + len(piece) <= max_chars:
            chunks[-1] += piece
        else:
            chunks.append(piece)
    return chunks


def wav_to_float(data: bytes) -> tuple[np.ndarray, int]:
    """16bit mono の WAV を float32 に開く。"""
    with wave.open(io.BytesIO(data), "rb") as source:
        if source.getsampwidth() != 2:
            raise ValueError(f"16bit の WAV ではありません（{source.getsampwidth() * 8}bit）")
        frames = source.readframes(source.getnframes())
        rate = source.getframerate()
        channels = source.getnchannels()
    samples = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32768.0
    if channels > 1:  # 念のため（AivisSpeech は mono を返す）
        samples = samples.reshape(-1, channels).mean(axis=1)
    return samples, rate


def float_to_wav(samples: np.ndarray, rate: int) -> bytes:
    """float32 を 16bit mono の WAV にする。ピークは -1 dBFS に揃える。"""
    peak = float(np.max(np.abs(samples))) if samples.size else 0.0
    if peak > 0:
        samples = samples * (TARGET_PEAK / peak)
    pcm = (np.clip(samples, -1.0, 1.0) * 32767.0).astype(np.int16)
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(rate)
        out.writeframes(pcm.tobytes())
    return buffer.getvalue()


class Aivis:
    """保険の AivisSpeech（VOICEVOX 互換の本物）。"""

    def __init__(self, url: str, speaker: int, timeout: float = 60.0) -> None:
        self.url = url.rstrip("/")
        self.speaker = speaker
        self.timeout = timeout

    def synthesize(self, text: str) -> tuple[np.ndarray, int]:
        query = urllib.parse.urlencode({"speaker": self.speaker, "text": text})
        request = urllib.request.Request(f"{self.url}/audio_query?{query}", method="POST")
        with urllib.request.urlopen(request, timeout=self.timeout) as response:
            audio_query = response.read()
        request = urllib.request.Request(
            f"{self.url}/synthesis?speaker={self.speaker}",
            data=audio_query,
            headers={"content-type": "application/json", "accept": "audio/wav"},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=self.timeout) as response:
            return wav_to_float(response.read())


class Engine:
    """モデルを抱えて合成する。

    MLX のストリームはスレッドごとなので、読み込みと生成は同じスレッドで動かす必要がある
    （別スレッドで generate すると "There is no Stream(cpu, 0) in current thread"）。
    そのため server は 1 スレッド（HTTPServer）で回す。presenta 側も 1 かたまりずつ順に待つので、
    同時に来ることはない。
    """

    def __init__(self, model_path: str, aivis: Aivis, budget_seconds: float) -> None:
        import mlx_speech  # 重いので、引数を捌いてから読む

        started = time.monotonic()
        self.model = mlx_speech.tts.load(model_path)
        self.aivis = aivis
        self.budget = budget_seconds
        self.seconds_per_char = INITIAL_SECONDS_PER_CHAR
        print(f"loaded {model_path} in {time.monotonic() - started:.1f}s", flush=True)

    def _fish(self, chunk: str) -> tuple[np.ndarray, int, float]:
        started = time.monotonic()
        out = self.model.generate(chunk)
        took = time.monotonic() - started
        samples = np.asarray(out.waveform, dtype=np.float32).reshape(-1)
        # 見積りを実測で更新する（原稿の書き方や機械の混み具合で変わるので）。
        if len(chunk) > 0:
            self.seconds_per_char = 0.5 * self.seconds_per_char + 0.5 * (took / len(chunk))
        return samples, int(out.sample_rate), took

    def synthesize(self, text: str) -> bytes:
        """原稿を読み上げて 44.1kHz mono 16bit の WAV にする。

        持ち時間を超えそうなかたまりは AivisSpeech に回す。1 枚のなかで声が変わることになるが、
        呼び出し側を待たせて失敗させるよりはよい（失敗するとその資料は動画にならない）。
        """
        chunks = split_text(text)
        if not chunks:
            raise ValueError("読み上げる原稿がありません")
        parts: list[np.ndarray] = []
        rate = 0
        used: list[str] = []
        started = time.monotonic()
        fell_back = False
        for chunk in chunks:
            elapsed = time.monotonic() - started
            estimate = len(chunk) * self.seconds_per_char
            if fell_back or elapsed + estimate > self.budget:
                if not fell_back:
                    print(
                        f"  budget: {elapsed:.0f}s 経過 + 見込み {estimate:.0f}s > {self.budget:.0f}s "
                        f"→ 残りは aivis",
                        flush=True,
                    )
                fell_back = True
                samples, rate = self.aivis.synthesize(chunk)
                used.append("aivis")
                print(f"  aivis {len(chunk)}字 -> {len(samples) / rate:.1f}s 音声", flush=True)
            else:
                try:
                    samples, rate, took = self._fish(chunk)
                except Exception as error:  # Fish が詰まった・落ちた
                    print(f"  fish 失敗（{error}）→ aivis に落とす", flush=True)
                    fell_back = True
                    samples, rate = self.aivis.synthesize(chunk)
                    used.append("aivis")
                else:
                    used.append("fish")
                    print(
                        f"  fish {len(chunk)}字 -> {len(samples) / rate:.1f}s 音声 / {took:.1f}s 生成",
                        flush=True,
                    )
            parts.append(samples)
        total = time.monotonic() - started
        merged = np.concatenate(parts)
        print(
            f"engine={'+'.join(sorted(set(used)))} chunks={len(chunks)} "
            f"audio={len(merged) / rate:.1f}s took={total:.1f}s",
            flush=True,
        )
        return float_to_wav(merged, rate)


class Handler(BaseHTTPRequestHandler):
    engine: Engine

    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args: object) -> None:
        # 既定は原稿を丸ごと URL で書くので長い。パスだけ残す。
        sys.stderr.write(f"{urlparse(self.path).path} {fmt % args}\n"[:200])

    def _send(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("content-type", content_type)
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _json(self, status: int, value: object) -> None:
        self._send(status, json.dumps(value, ensure_ascii=False).encode(), "application/json")

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/version":
            self._json(200, "fish-s2-pro-shim/0.2")
        elif path == "/speakers":
            self._json(
                200,
                [
                    {
                        "name": SPEAKER_NAME,
                        "speaker_uuid": "00000000-0000-4000-8000-000000000001",
                        "styles": [{"name": "ノーマル", "id": SPEAKER_ID, "type": "talk"}],
                        "version": "0.2",
                        "supported_features": {"permitted_synthesis_morphing": "NOTHING"},
                    }
                ],
            )
        else:
            self._json(404, {"detail": "not found"})

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)
        if parsed.path == "/audio_query":
            text = (query.get("text") or [""])[0]
            if not text.strip():
                self._json(422, {"detail": "text is required"})
                return
            # VOICEVOX のクエリの形に寄せておく（presenta はそのまま /synthesis に渡すだけ）。
            self._json(
                200,
                {
                    "accent_phrases": [],
                    "speedScale": 1.0,
                    "pitchScale": 0.0,
                    "intonationScale": 1.0,
                    "volumeScale": 1.0,
                    "prePhonemeLength": 0.1,
                    "postPhonemeLength": 0.1,
                    "outputSamplingRate": 44100,
                    "outputStereo": False,
                    "kana": text,
                    # シムの本体。読み上げる原稿はここで往復させる。
                    "text": text,
                },
            )
            return
        if parsed.path == "/synthesis":
            length = int(self.headers.get("content-length") or 0)
            try:
                body = json.loads(self.rfile.read(length) or b"{}")
                text = str(body.get("text") or body.get("kana") or "")
                wav = self.engine.synthesize(text)
            except Exception as error:
                print(f"synthesis 失敗: {error}", flush=True)
                self._json(500, {"detail": str(error)})
                return
            self._send(200, wav, "audio/wav")
            return
        self._json(404, {"detail": "not found"})


def selftest() -> None:
    """切り方と WAV の往復だけ確かめる（モデルを読まずに走る）。"""
    assert split_text("") == []
    assert split_text("   ") == []
    assert split_text("あ。い。") == ["あ。い。"]
    # 上限を超えたら次のかたまりへ送る
    assert split_text("あ" * 70 + "。" + "い" * 70 + "。", 120) == ["あ" * 70 + "。", "い" * 70 + "。"]
    # 上限より長い 1 文は切らない（切ると読みが壊れる）
    long_one = "う" * 300 + "。"
    assert split_text(long_one, 120) == [long_one]
    # 句点の後ろで切るので、繋ぎ直しても原文は保たれる
    text = "本日はありがとうございます。中町商店街は42パーセント減りました。以上です。"
    assert "".join(split_text(text, 20)) == text

    # WAV の往復。ピークは -1dBFS に揃う。
    tone = (np.sin(np.arange(4410) * 0.1) * 0.05).astype(np.float32)
    back, rate = wav_to_float(float_to_wav(tone, 44100))
    assert rate == 44100 and back.size == tone.size
    assert abs(float(np.max(np.abs(back))) - TARGET_PEAK) < 0.01, float(np.max(np.abs(back)))
    # 無音を渡しても割り算で落ちない
    silent, _ = wav_to_float(float_to_wav(np.zeros(100, dtype=np.float32), 44100))
    assert float(np.max(np.abs(silent))) == 0.0
    print("selftest ok")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=10202)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--model", default="fish-s2-pro")
    parser.add_argument("--aivis-url", default="http://100.105.135.49:10101")
    parser.add_argument("--aivis-speaker", type=int, default=888753760)
    parser.add_argument(
        "--budget-seconds",
        type=float,
        default=90.0,
        help="1 回の /synthesis に使ってよい秒数。超えそうなぶんは AivisSpeech に回す。"
        " 呼び出し側（presenta）は 120 秒で諦めるので、それより短くすること。",
    )
    parser.add_argument("--selftest", action="store_true", help="切り方と WAV の往復を確かめて終わる")
    args = parser.parse_args()

    if args.selftest:
        selftest()
        return

    aivis = Aivis(args.aivis_url, args.aivis_speaker)
    Handler.engine = Engine(args.model, aivis, args.budget_seconds)
    server = HTTPServer((args.host, args.port), Handler)
    print(
        f"fish voicevox shim on http://{args.host}:{args.port} "
        f"(budget={args.budget_seconds:.0f}s, fallback={args.aivis_url})",
        flush=True,
    )
    server.serve_forever()


if __name__ == "__main__":
    main()
