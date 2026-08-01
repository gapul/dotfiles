#!/bin/bash
# まず mopidy(MPD 127.0.0.1:6600) を直接読み、再生中なら mopidy を表示する。
# mopidy は macOS の Now Playing に名乗れない(macOS 26 制限)ので media-control では
# 拾えないため、MPD を直接叩く。mopidy が止まっていれば従来どおり media-control
# (他アプリの Now Playing) にフォールバックする。
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/icons.sh"

MOPIDY=$(python3 - <<'PY' 2>/dev/null
import socket
try:
    s = socket.create_connection(("127.0.0.1", 6600), timeout=1); s.recv(256)
    def req(c):
        s.sendall((c + "\n").encode()); s.settimeout(1); b = b""
        while not b.rstrip().endswith(b"OK") and b"\nACK" not in b:
            d = s.recv(4096)
            if not d: break
            b += d
        return b.decode("utf-8", "replace")
    def parse(t):
        o = {}
        for l in t.splitlines():
            if ": " in l:
                k, v = l.split(": ", 1); o.setdefault(k, v)
        return o
    st = parse(req("status")); sg = parse(req("currentsong")); s.close()
    stt = st.get("state")
    if stt in ("play", "pause"):
        print(stt + "\t" + sg.get("Title", "") + "\t" + (sg.get("Artist") or sg.get("AlbumArtist") or ""))
except Exception:
    pass
PY
)

if [ -n "$MOPIDY" ]; then
  IFS=$'\t' read -r MSTATE TITLE ARTIST <<< "$MOPIDY"
  if [ -n "$TITLE" ] && [ -n "$ARTIST" ]; then LABEL="$TITLE — $ARTIST"
  elif [ -n "$TITLE" ]; then LABEL="$TITLE"
  else LABEL="$ARTIST"; fi
  if [ "$MSTATE" = "pause" ]; then MCOL="$YELLOW"; else MCOL="$GREEN"; fi
  MICON="􀑪"
  # トグルボタン: 再生中は一時停止アイコン、停止中は再生アイコン
  if [ "$MSTATE" = "play" ]; then sketchybar --set music.toggle icon="$MUSIC_PAUSED"; else sketchybar --set music.toggle icon="$MUSIC_PLAYING"; fi
  sketchybar --set "$NAME" icon="$MICON" icon.color="$MCOL" label="$LABEL" drawing=on
  exit 0
fi

# --- mopidy 停止時: media-control で他アプリの Now Playing を表示 ---
RESULT=$(/opt/homebrew/bin/media-control get 2>/dev/null \
  | "$HOME/.nix-profile/bin/jq" -r '
      if . == null or (. | type) != "object" then "none\t\t"
      else ((.playing // (.playbackRate // 0) > 0) | if . then "playing" else "paused" end)
        + "\t" + ((.title // "") | gsub("\t"; " "))
        + "\t" + ((.artist // "") | gsub("\t"; " ")) end' 2>/dev/null)

if [ -z "$RESULT" ]; then sketchybar --set "$NAME" drawing=off; exit 0; fi
IFS=$'\t' read -r STATUS TITLE ARTIST <<< "$RESULT"
if [ "$STATUS" != "playing" ]; then sketchybar --set "$NAME" drawing=off; exit 0; fi
if [ -n "$TITLE" ] && [ -n "$ARTIST" ]; then LABEL="$TITLE — $ARTIST"
elif [ -n "$TITLE" ]; then LABEL="$TITLE"; else LABEL="$ARTIST"; fi
sketchybar --set "$NAME" icon="􀑪" icon.color="$GREEN" label="$LABEL" drawing=on
