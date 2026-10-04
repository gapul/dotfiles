"""Pairing page for the T3 Code server on this machine (t3pair.gapul.net).

Each press mints a one-time 5-minute pairing link for https://t3.gapul.net and shows
it as text and a QR code. Once a device uses the link, the page mints the next one, so
a link already spent on the phone is never pasted into another device. A link grants agent access to this machine, so the page is
served only through the homeserver's Caddy behind Authelia: requests from any other
address are refused, and only /health answers without Authelia's Remote-User header.
"""

import json
import os
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("T3_PAIR_PORT", "3774"))
CADDY_ADDR = os.environ.get("T3_PAIR_CADDY_ADDR", "100.127.129.31")
BASE_URL = os.environ.get("T3_PAIR_BASE_URL", "https://t3.gapul.net")
T3 = os.path.expanduser("~/.local/bin/t3")
QRENCODE = os.environ.get("T3_PAIR_QRENCODE", "qrencode")

PAGE = """<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>T3 Pair</title>
<style>
  :root { color-scheme: light dark; --fg: #1a1a1a; --bg: #f6f6f4; --muted: #6b6b6b; --card: #fff; }
  @media (prefers-color-scheme: dark) { :root { --fg: #eee; --bg: #161616; --muted: #9a9a9a; --card: #222; } }
  body { margin: 0; padding: 24px 16px; font: 15px/1.5 system-ui, sans-serif; background: var(--bg); color: var(--fg); }
  main { max-width: 420px; margin: 0 auto; text-align: center; }
  h1 { font-size: 18px; margin: 0 0 16px; }
  #qr { background: #fff; border-radius: 12px; padding: 12px; aspect-ratio: 1; }
  #qr svg { width: 100%; height: 100%; display: block; }
  #qr.expired { opacity: .15; }
  #url { word-break: break-all; font: 13px ui-monospace, monospace; background: var(--card); padding: 10px; border-radius: 8px; margin: 12px 0; text-align: left; }
  #status { color: var(--muted); min-height: 1.5em; }
  button { font: inherit; padding: 10px 18px; border-radius: 8px; border: 1px solid var(--muted); background: var(--card); color: var(--fg); margin: 4px; }
</style>
</head>
<body>
<main>
  <h1>T3 Code ペアリング</h1>
  <div id="qr"></div>
  <div id="url"></div>
  <div id="status"></div>
  <button id="new">新しいリンク</button>
  <button id="copy">URLをコピー</button>
</main>
<script>
let expiresAt = 0, url = "", id = "", note = "";
const $ = (id) => document.getElementById(id);
async function mint() {
  $("status").textContent = "発行中…";
  const r = await fetch("new", { method: "POST" });
  if (!r.ok) { $("status").textContent = "発行に失敗しました (" + r.status + ")"; return; }
  const d = await r.json();
  url = d.url; id = d.id; expiresAt = Date.parse(d.expiresAt);
  $("qr").innerHTML = d.svg; $("qr").classList.remove("expired"); $("url").textContent = url;
  tick();
}
function tick() {
  if (!expiresAt) return;
  const s = Math.round((expiresAt - Date.now()) / 1000);
  if (s <= 0) { $("qr").classList.add("expired"); $("status").textContent = "期限切れ。新しいリンクを発行してください"; return; }
  $("status").textContent = note + "残り " + Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0") + "(1回限り)";
}
async function poll() {
  if (!id || document.hidden || expiresAt <= Date.now()) return;
  const r = await fetch("status?id=" + encodeURIComponent(id));
  if (r.ok && !(await r.json()).active && expiresAt > Date.now()) {
    note = "前のリンクで接続されました。次のリンク: ";
    mint();
  }
}
setInterval(tick, 1000);
setInterval(poll, 3000);
$("new").onclick = () => { note = ""; mint(); };
$("copy").onclick = async () => { if (url) { await navigator.clipboard.writeText(url); $("status").textContent = "コピーしました"; } };
mint();
</script>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    def send(self, code, body, ctype="text/plain; charset=utf-8"):
        data = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def allowed(self, need_user=True):
        if self.client_address[0] not in (CADDY_ADDR, "127.0.0.1"):
            return False
        return not need_user or bool(self.headers.get("Remote-User"))

    def do_GET(self):
        if self.path == "/health":
            return self.send(200 if self.allowed(need_user=False) else 403, "ok")
        if not self.allowed():
            return self.send(403, "forbidden")
        if self.path == "/":
            return self.send(200, PAGE, "text/html; charset=utf-8")
        if self.path.startswith("/status?id="):
            # A consumed or revoked link drops out of the active list.
            pid = self.path.split("=", 1)[1]
            try:
                active = subprocess.run(
                    [T3, "auth", "pairing", "list", "--json"],
                    capture_output=True, text=True, timeout=30, check=True,
                ).stdout
                ids = {p["id"] for p in json.loads(active)}
            except (subprocess.SubprocessError, OSError, ValueError, KeyError):
                return self.send(502, "list failed")
            return self.send(200, json.dumps({"active": pid in ids}), "application/json")
        self.send(404, "not found")

    def do_POST(self):
        if not self.allowed():
            return self.send(403, "forbidden")
        if self.path != "/new":
            return self.send(404, "not found")
        try:
            out = subprocess.run(
                [T3, "auth", "pairing", "create", "--ttl", "5m", "--label", "pair-page",
                 "--base-url", BASE_URL, "--json"],
                capture_output=True, text=True, timeout=30, check=True,
            ).stdout
            pair = json.loads(out)
            svg = subprocess.run(
                [QRENCODE, "-t", "SVG", "-m", "1", "-o", "-", pair["pairUrl"]],
                capture_output=True, text=True, timeout=10, check=True,
            ).stdout
        except (subprocess.SubprocessError, OSError, ValueError, KeyError) as e:
            self.log_error("mint failed: %s", type(e).__name__)
            return self.send(502, "mint failed")
        body = {"id": pair["id"], "url": pair["pairUrl"], "expiresAt": pair["expiresAt"], "svg": svg}
        self.send(200, json.dumps(body), "application/json")


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
