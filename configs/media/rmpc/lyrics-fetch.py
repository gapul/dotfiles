#!/usr/bin/env python3
# rmpc の on_song_change から呼ばれ、現在再生中の曲の歌詞(.lrc)を lyrics_dir に書き出す。
# 取得は lrclib.net(同期歌詞) を優先し、無ければ YouTube Music(ytmusicapi get_lyrics,
# 非同期) にフォールバック。rmpc は .lrc の [ar:][ti:][al:][length:] メタで曲にマッチする。
# MPD を自分で読むので rmpc の env var 名には依存しない。ytmusicapi を使うため mopidy env
# の python で実行する想定 (auth は ~/.config/mopidy/browser.json)。
import os
import re
import json
import socket
import urllib.parse
import urllib.request

LYRICS_DIR = os.path.expanduser("~/.cache/rmpc/lyrics")
AUTH = os.path.expanduser("~/.config/mopidy/browser.json")
MPD = ("127.0.0.1", 6600)


def mpd_currentsong():
    s = socket.create_connection(MPD, timeout=5)
    s.recv(4096)  # greeting
    s.sendall(b"currentsong\n")
    buf = b""
    s.settimeout(5)
    while not buf.rstrip().endswith(b"OK") and b"\nACK" not in buf:
        chunk = s.recv(4096)
        if not chunk:
            break
        buf += chunk
    s.close()
    info = {}
    for line in buf.decode("utf-8", "replace").splitlines():
        if ": " in line:
            k, v = line.split(": ", 1)
            info.setdefault(k, v)
    return info


def sanitize(name):
    return re.sub(r"[^\w\- ().]", "_", name)[:80]


def lrc_headers(artist, title, album, dur):
    h = [f"[ar:{artist}]", f"[ti:{title}]"]
    if album:
        h.append(f"[al:{album}]")
    if dur:
        h.append(f"[length:{int(dur)//60:02d}:{int(dur)%60:02d}]")
    return "\n".join(h) + "\n"


def fetch_lrclib(artist, title, album, dur):
    q = urllib.parse.urlencode(
        {"artist_name": artist, "track_name": title, "album_name": album or "",
         "duration": int(dur) if dur else ""}
    )
    try:
        req = urllib.request.Request(
            "https://lrclib.net/api/get?" + q,
            headers={"User-Agent": "rmpc-lyrics-fetch (mopidy)"},
        )
        with urllib.request.urlopen(req, timeout=8) as r:
            d = json.load(r)
        return d.get("syncedLyrics") or d.get("plainLyrics")
    except Exception:
        return None


def fetch_ytmusic(file_uri):
    if not file_uri.startswith("ytmusic:track:"):
        return None
    vid = file_uri.split(":")[2]
    try:
        from ytmusicapi import YTMusic
        yt = YTMusic(auth=AUTH)
        wp = yt.get_watch_playlist(videoId=vid)
        lid = wp.get("lyrics")
        if not lid:
            return None
        return (yt.get_lyrics(lid) or {}).get("lyrics")
    except Exception:
        return None


def main():
    info = mpd_currentsong()
    artist = info.get("Artist") or info.get("AlbumArtist") or ""
    title = info.get("Title") or ""
    album = info.get("Album") or ""
    dur = info.get("duration") or info.get("Time") or ""
    file_uri = info.get("file") or ""
    if not (artist and title):
        return
    os.makedirs(LYRICS_DIR, exist_ok=True)
    path = os.path.join(LYRICS_DIR, f"{sanitize(artist)} - {sanitize(title)}.lrc")
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return  # キャッシュ済み

    body = fetch_lrclib(artist, title, album, dur) or fetch_ytmusic(file_uri)
    if not body:
        return
    with open(path, "w", encoding="utf-8") as f:
        f.write(lrc_headers(artist, title, album, dur))
        f.write(body if body.endswith("\n") else body + "\n")


if __name__ == "__main__":
    main()
