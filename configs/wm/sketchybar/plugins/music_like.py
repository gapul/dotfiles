# mopidy の現在曲(file=ytmusic:track:VID)を YouTube Music で LIKE する。
# mopidy env の python(ytmusicapi あり)で実行する想定。auth=~/.config/mopidy/browser.json。
import socket, os

def mpd(cmd):
    s = socket.create_connection(("127.0.0.1", 6600), timeout=2); s.recv(256)
    s.sendall((cmd + "\n").encode()); s.settimeout(2); b = b""
    while not b.rstrip().endswith(b"OK") and b"\nACK" not in b:
        d = s.recv(4096)
        if not d: break
        b += d
    s.close(); return b.decode("utf-8", "replace")

info = {}
for l in mpd("currentsong").splitlines():
    if ": " in l:
        k, v = l.split(": ", 1); info.setdefault(k, v)
uri = info.get("file", "")
if uri.startswith("ytmusic:track:"):
    vid = uri.split(":")[2]
    from ytmusicapi import YTMusic
    yt = YTMusic(auth=os.path.expanduser("~/.config/mopidy/browser.json"))
    yt.rate_song(vid, "LIKE")
    print("liked", vid)
