#!/usr/bin/env python3
"""mopidy-ytmusic の YouTube 認証 cookie を Chrome から取り直す。

YouTube のセッション cookie (__Secure-1PSIDTS / __Secure-3PSIDTS) は数時間で
ローテーションし、静的にコピーしたものは短時間で無効になる。Chrome が動いている間は
Chrome 自身が更新し続けるので、定期的に Chrome を起動 → cookie 抽出 → 検証 →
mopidy が読むファイルへ書き出す、を回して延命する。

- 自動化専用プロファイル (~/Library/Application Support/Google/Chrome-automation) を使う。
  ユーザーが Dock から開いた通常の Chrome は巻き込まない。
- 検証に通った cookie だけ書き出す。ダメなら既存ファイルを温存する (Chrome 側の
  Google セッションごと切れている場合は人間の再ログインが要る)。
- 認証は mopidy の起動時に一度しか読まれないので、更新できたら mopidy を再起動する。
  ただし再生中は音が途切れるので、止まっているときだけ。

--dry-run で書き出しと再起動をせず、抽出と検証だけ行う (動作確認用)。
"""

import json
import os
import socket
import subprocess
import sys
import time

PROFILE_DIR = os.path.expanduser(
    "~/Library/Application Support/Google/Chrome-automation"
)
LIVE_PATH = os.path.expanduser("~/.local/state/mopidy/browser.json")
SEED_PATH = os.path.expanduser("~/.config/mopidy/browser.json")
CHROME = "/Applications/Google Chrome.app"
MOPIDY_LABEL = "org.nix-community.home.mopidy"
DRY_RUN = "--dry-run" in sys.argv


def log(msg):
    print(f"[refresh-cookies] {msg}", flush=True)


def chrome_running():
    return (
        subprocess.run(
            ["/usr/bin/pgrep", "-f", "Chrome-automation"],
            capture_output=True,
        ).returncode
        == 0
    )


def start_chrome():
    # 背景・非アクティブで起動してフォーカスを奪わない (--headless=new は拡張が動かないので使わない)。
    # --no-startup-window ではページを読まないので cookie が更新されない。実際に
    # music.youtube.com を開かせることで Chrome にセッションを更新させる。
    subprocess.run(
        [
            "/usr/bin/open",
            "-gjn",
            "-a",
            CHROME,
            "--args",
            f"--user-data-dir={PROFILE_DIR}",
            "https://music.youtube.com/",
        ],
        check=True,
    )
    time.sleep(20)  # ページ読み込みと cookie の更新が走るまで待つ


def stop_chrome():
    subprocess.run(["/usr/bin/pkill", "-f", "Chrome-automation"], capture_output=True)


def build_headers(cookie):
    from ytmusicapi.helpers import get_authorization, sapisid_from_cookie

    base = {}
    for path in (LIVE_PATH, SEED_PATH):
        try:
            with open(path) as f:
                base = json.load(f)
            break
        except Exception:
            continue
    headers = {
        "User-Agent": base.get("User-Agent")
        or "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36",
        "Accept": "*/*",
        "Accept-Language": "en-US,en;q=0.5",
        "Content-Type": "application/json",
        "X-Goog-AuthUser": "0",
        "x-origin": "https://music.youtube.com",
        "cookie": cookie,
        "authorization": get_authorization(
            sapisid_from_cookie(cookie) + " https://music.youtube.com"
        ),
    }
    return headers


def extract_cookie():
    from yt_dlp.cookies import extract_cookies_from_browser

    jar = extract_cookies_from_browser(
        "chrome", profile=os.path.join(PROFILE_DIR, "Default")
    )
    pairs = {c.name: c.value for c in jar if c.domain.endswith("youtube.com")}
    if "SAPISID" not in pairs:
        raise RuntimeError("SAPISID cookie not found")
    return "; ".join(f"{k}={v}" for k, v in pairs.items())


def is_authenticated(headers):
    from ytmusicapi import YTMusic

    yt = YTMusic(json.dumps(headers))
    # ライブラリが空でも 0 件は返りうるので、認証必須の履歴と合わせて判定する。
    # 未ログインだと 0 件で返る場合と例外になる場合の両方がある。
    for call in (lambda: yt.get_library_songs(limit=5), yt.get_history):
        try:
            if call():
                return True
        except Exception:
            continue
    return False


def mpd_state():
    try:
        s = socket.create_connection(("127.0.0.1", 6600), timeout=5)
        s.recv(4096)
        s.sendall(b"status\nclose\n")
        buf = b""
        s.settimeout(5)
        while True:
            c = s.recv(4096)
            if not c:
                break
            buf += c
        s.close()
        for line in buf.decode("utf-8", "replace").splitlines():
            if line.startswith("state: "):
                return line.split(": ", 1)[1]
    except Exception:
        pass
    return None


def main():
    started_chrome = False
    if not chrome_running():
        log("starting Chrome (automation profile)")
        start_chrome()
        started_chrome = True
    try:
        cookie = extract_cookie()
        headers = build_headers(cookie)
        if not is_authenticated(headers):
            log("FAILED: Chrome のセッションが切れている。手動での再ログインが必要")
            return 1
    finally:
        if started_chrome:
            stop_chrome()

    new = json.dumps(headers)
    try:
        with open(LIVE_PATH) as f:
            if f.read().strip() == new:
                log("cookie unchanged")
                return 0
    except Exception:
        pass

    if DRY_RUN:
        log("OK (dry run): 認証は有効。書き出しと再起動はしていない")
        return 0

    os.makedirs(os.path.dirname(LIVE_PATH), exist_ok=True)
    tmp = LIVE_PATH + ".new"
    with open(tmp, "w") as f:
        f.write(new)
    os.chmod(tmp, 0o600)
    os.replace(tmp, LIVE_PATH)
    log("wrote " + LIVE_PATH)

    state = mpd_state()
    if state == "play":
        log("mopidy は再生中なので再起動しない (次回に持ち越し)")
        return 0
    subprocess.run(
        [
            "/bin/launchctl",
            "kickstart",
            "-k",
            f"gui/{os.getuid()}/{MOPIDY_LABEL}",
        ],
        capture_output=True,
    )
    log("restarted mopidy")
    return 0


if __name__ == "__main__":
    sys.exit(main())
