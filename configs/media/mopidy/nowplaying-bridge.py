#!/usr/bin/env python3
"""macOS の再生コントロール (Now Playing / メディアキー / AirPods) と mopidy をつなぐ常駐プロセス。

mopidy 本体から MPRemoteCommandCenter に登録しても、押されたキーは届かない。本体スレッドは
GLib のループを回していて、macOS が操作を配達するのに使う Cocoa のランループが無いためで、
状態の通知 (こちらから押し出す) だけが動き、操作 (向こうから来る) は落ちるという非対称になる。

そこで受け口だけを別プロセスに出す。こちらは Cocoa のランループを回し、
- 押された操作は MPD (127.0.0.1:6600) のコマンドに翻訳して mopidy に渡す
- 再生中の曲と経過時間は MPD から読んで Now Playing に出す
署名や entitlement は要らない (実測: 素のプロセスでもキーは届く)。
"""

import logging
import socket
import sys

import objc
from AppKit import NSApplication, NSApplicationActivationPolicyAccessory
from Foundation import NSBundle, NSTimer

logging.basicConfig(level=logging.INFO, format="[nowplaying] %(message)s")
logger = logging.getLogger()

MPD = ("127.0.0.1", 6600)
POLL_INTERVAL = 1.0

# バンドルを持たない素の python プロセスのままだと mediaremoted 上の名前が python3.13 に
# なるので、名乗りを差し込んでおく。
_main = NSBundle.mainBundle()
_info = _main.localizedInfoDictionary() or _main.infoDictionary()
if _info is not None:
    _info["CFBundleIdentifier"] = "net.gapul.mopidy-nowplaying"
    _info["CFBundleName"] = "Mopidy"
    _info["CFBundleDisplayName"] = "Mopidy"

NSBundle.bundleWithPath_("/System/Library/Frameworks/MediaPlayer.framework").load()
_MP = objc.lookUpClass("MPNowPlayingInfoCenter")
_RC = objc.lookUpClass("MPRemoteCommandCenter")
# pyobjc-framework-MediaPlayer が無いのでブロックの署名を手で登録する。
# MPRemoteCommandHandlerStatus(NSInteger 'q') (^)(MPRemoteCommandEvent* '@')
objc.registerMetaDataForSelector(
    b"MPRemoteCommand",
    b"addTargetWithHandler:",
    {
        "arguments": {
            2: {
                "type": b"@?",
                "callable": {
                    "retval": {"type": b"q"},
                    "arguments": {0: {"type": b"^v"}, 1: {"type": b"@"}},
                },
            }
        }
    },
)

K_TITLE = "title"
K_ARTIST = "artist"
K_ALBUM = "albumTitle"
K_DURATION = "playbackDuration"
K_ELAPSED = "MPNowPlayingInfoPropertyElapsedPlaybackTime"
K_RATE = "MPNowPlayingInfoPropertyPlaybackRate"
PS_PLAYING, PS_PAUSED, PS_STOPPED = 1, 2, 3


def mpd(*commands):
    """MPD にコマンドを送って応答を dict で返す。落ちていても例外は投げない。"""
    try:
        s = socket.create_connection(MPD, timeout=5)
        s.recv(4096)  # greeting
        s.sendall(("\n".join(commands) + "\nclose\n").encode())
        buf = b""
        s.settimeout(5)
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
        s.close()
    except Exception:
        return None
    out = {}
    for line in buf.decode("utf-8", "replace").splitlines():
        if ": " in line:
            key, value = line.split(": ", 1)
            out.setdefault(key, value)
    return out


class Bridge:
    def __init__(self):
        self.center = _MP.defaultCenter()
        self._handlers = []  # ブロックの参照を保持 (GC 防止)
        self._last = None

    def setup_commands(self):
        cc = _RC.sharedCommandCenter()

        def register(command, action, name):
            def handler(event):
                try:
                    action()
                    self.update()
                except Exception:
                    logger.exception("command %s failed", name)
                return 0  # MPRemoteCommandHandlerStatusSuccess

            self._handlers.append(handler)
            command.setEnabled_(True)
            command.addTargetWithHandler_(handler)

        register(cc.playCommand(), lambda: mpd("play"), "play")
        register(cc.pauseCommand(), lambda: mpd("pause 1"), "pause")
        register(cc.togglePlayPauseCommand(), self.toggle, "toggle")
        register(cc.nextTrackCommand(), lambda: mpd("next"), "next")
        register(cc.previousTrackCommand(), lambda: mpd("previous"), "previous")
        register(cc.stopCommand(), lambda: mpd("stop"), "stop")

    def toggle(self):
        status = mpd("status") or {}
        # play は「停止から再生」、pause 0/1 は「一時停止の切り替え」で別物
        if status.get("state") == "stop":
            mpd("play")
        else:
            mpd("pause")

    def update(self):
        status = mpd("status")
        if status is None:
            return
        state = status.get("state")
        if state in (None, "stop"):
            if self._last is not None:
                self.center.setNowPlayingInfo_(None)
                self.center.setPlaybackState_(PS_STOPPED)
                self._last = None
            return
        song = mpd("currentsong") or {}
        info = {
            K_TITLE: song.get("Title") or song.get("file") or "",
            K_ARTIST: song.get("Artist") or "",
            K_ALBUM: song.get("Album") or "",
            K_DURATION: float(status.get("duration") or 0.0),
            K_ELAPSED: float(status.get("elapsed") or 0.0),
            K_RATE: 1.0 if state == "play" else 0.0,
        }
        # 経過時間だけの差分で毎秒書き換えると無駄なので、曲か再生状態が変わったときだけ出す
        key = (info[K_TITLE], info[K_ARTIST], info[K_ALBUM], state)
        if key != self._last:
            self._last = key
            logger.info("now playing: %s - %s (%s)", info[K_ARTIST], info[K_TITLE], state)
        self.center.setNowPlayingInfo_(info)
        self.center.setPlaybackState_(PS_PLAYING if state == "play" else PS_PAUSED)


def main():
    app = NSApplication.sharedApplication()
    # メニューバーにも Dock にも出さない常駐プロセスにする
    app.setActivationPolicy_(NSApplicationActivationPolicyAccessory)

    bridge = Bridge()
    bridge.setup_commands()
    bridge.update()

    NSTimer.scheduledTimerWithTimeInterval_repeats_block_(
        POLL_INTERVAL, True, lambda timer: bridge.update()
    )
    logger.info("started")
    sys.stdout.flush()
    app.run()


if __name__ == "__main__":
    main()
