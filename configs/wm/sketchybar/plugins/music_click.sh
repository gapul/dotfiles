#!/bin/bash
ACTION="${1:-toggle}"
if [ "$SENDER" = "mouse.entered" ]; then sketchybar --set music popup.drawing=on; exit 0; fi
if [ "$SENDER" = "mouse.exited" ]; then sketchybar --set music popup.drawing=off; exit 0; fi

# バークリック: タイトル右の操作アイコンをトグル表示
if [ "$ACTION" = "controls" ]; then
  cur=$(sketchybar --query music.prev 2>/dev/null | python3 -c "import sys,json;print(json.load(sys.stdin).get('geometry',{}).get('drawing','off'))" 2>/dev/null)
  if [ "$cur" = "on" ]; then new=off; else new=on; fi
  for b in music.prev music.toggle music.next music.like; do
    sketchybar --set "$b" drawing=$new
  done
  exit 0
fi

if [ "$ACTION" = "like" ]; then
  # mopidy env の python(ytmusicapiあり)を launchd startScript から特定して like 実行
  STARTSH=$(/usr/bin/plutil -extract ProgramArguments.0 raw "$HOME/Library/LaunchAgents/org.nix-community.home.mopidy.plist" 2>/dev/null)
  ENV=$(grep -oE '/nix/store/[^ ]*python3-3.13.13-env' "$STARTSH" 2>/dev/null | head -1)
  [ -n "$ENV" ] && "$ENV/bin/python" "$CONFIG_DIR/plugins/music_like.py" >/dev/null 2>&1
  sketchybar --set music.like icon.color=$RED
  exit 0
fi

python3 - "$ACTION" <<'PY' 2>/dev/null
import sys, socket
act = sys.argv[1]
try:
    s = socket.create_connection(("127.0.0.1", 6600), timeout=1); s.recv(256)
    def req(c):
        s.sendall((c + "\n").encode()); s.settimeout(1); b = b""
        while not b.rstrip().endswith(b"OK") and b"\nACK" not in b:
            d = s.recv(4096)
            if not d: break
            b += d
        return b.decode("utf-8", "replace")
    if act == "next": req("next")
    elif act == "prev": req("previous")
    elif act == "seekfwd": req("seekcur +10")
    elif act == "seekback": req("seekcur -10")
    else:
        st = {}
        for l in req("status").splitlines():
            if ": " in l: k, v = l.split(": ", 1); st.setdefault(k, v)
        state = st.get("state")
        if state == "play": req("pause 1")
        elif state == "pause": req("play")
    s.close()
except Exception:
    pass
PY
NAME=music PLUGIN_DIR="$PLUGIN_DIR" CONFIG_DIR="$CONFIG_DIR" bash "$PLUGIN_DIR/music.sh"
