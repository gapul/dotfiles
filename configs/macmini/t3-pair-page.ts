#!/usr/bin/env bun
// Pairing page for the T3 Code server on this machine (t3pair.gapul.net).
//
// Each press mints a one-time 5-minute pairing link for https://t3.gapul.net and shows
// it as text and a QR code. Once a device uses the link, the page mints the next one, so
// a link already spent on the phone is never pasted into another device. A link grants agent access to this machine, so the page is
// served only through the homeserver's Caddy behind Authelia: requests from any other
// address are refused, and only /health answers without Authelia's Remote-User header.
//
// Ported from t3-pair-page.py: same port, routes, status codes, bodies and access-log lines.
import { homedir } from "node:os";

const PORT = Number.parseInt(process.env.T3_PAIR_PORT ?? "3774", 10);
const CADDY_ADDR = process.env.T3_PAIR_CADDY_ADDR ?? "100.127.129.31";
const BASE_URL = process.env.T3_PAIR_BASE_URL ?? "https://t3.gapul.net";
const T3 = `${homedir()}/.local/bin/t3`;
const QRENCODE = process.env.T3_PAIR_QRENCODE ?? "qrencode";

const PAGE = `<!doctype html>
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
`;

class SubprocessError extends Error {}

// subprocess.run(cmd, capture_output=True, text=True, timeout=..., check=True).stdout; errors are
// named like Python's so the log line stays the same.
async function run(cmd: string[], timeoutSeconds: number): Promise<string> {
  let proc: Bun.Subprocess<"ignore", "pipe", "pipe">;
  try {
    proc = Bun.spawn(cmd, { stdin: "ignore", stdout: "pipe", stderr: "pipe" });
  } catch {
    throw new SubprocessError("FileNotFoundError");
  }
  let timedOut = false;
  const timer = setTimeout(() => {
    timedOut = true;
    proc.kill("SIGKILL");
  }, timeoutSeconds * 1000);
  const [stdout] = await Promise.all([new Response(proc.stdout).text(), new Response(proc.stderr).text()]);
  const code = await proc.exited;
  clearTimeout(timer);
  if (timedOut) throw new SubprocessError("TimeoutExpired");
  if (code !== 0) throw new SubprocessError("CalledProcessError");
  return stdout;
}

function parseJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    throw new SubprocessError("JSONDecodeError");
  }
}

// d[k] with Python's KeyError
function key(d: unknown, k: string): unknown {
  if (d === null || typeof d !== "object" || !(k in d)) throw new SubprocessError("KeyError");
  return (d as Record<string, unknown>)[k];
}

// json.dumps (ensure_ascii, ", " / ": " separators) for the flat objects answered here
function dumps(v: Record<string, unknown>): string {
  const str = (x: unknown) =>
    JSON.stringify(x).replace(/[\u007f-\uffff]/g, (c) => `\\u${c.charCodeAt(0).toString(16).padStart(4, "0")}`);
  return `{${Object.entries(v)
    .map(([k, x]) => `${str(k)}: ${str(x)}`)
    .join(", ")}}`;
}

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

// BaseHTTPRequestHandler.log_message: "<client> - - [23/Oct/2026 18:00:00] <message>"
function log(client: string, message: string): void {
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, "0");
  const when = `${p(d.getDate())}/${MONTHS[d.getMonth()]}/${d.getFullYear()} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
  process.stderr.write(`${client} - - [${when}] ${message}\n`);
}

function send(code: number, body: string, ctype = "text/plain; charset=utf-8"): Response {
  return new Response(body, {
    status: code,
    headers: { "Content-Type": ctype, "Cache-Control": "no-store" },
  });
}

async function handle(req: Request, client: string, path: string): Promise<Response> {
  const allowed = (needUser = true) =>
    (client === CADDY_ADDR || client === "127.0.0.1") && (!needUser || Boolean(req.headers.get("Remote-User")));

  if (req.method === "GET") {
    if (path === "/health") return send(allowed(false) ? 200 : 403, "ok");
    if (!allowed()) return send(403, "forbidden");
    if (path === "/") return send(200, PAGE, "text/html; charset=utf-8");
    if (path.startsWith("/status?id=")) {
      // A consumed or revoked link drops out of the active list.
      const pid = path.slice(path.indexOf("=") + 1);
      let ids: Set<unknown>;
      try {
        const active = await run([T3, "auth", "pairing", "list", "--json"], 30);
        ids = new Set((parseJson(active) as unknown[]).map((p) => key(p, "id")));
      } catch (e) {
        if (e instanceof SubprocessError) return send(502, "list failed");
        throw e;
      }
      return send(200, dumps({ active: ids.has(pid) }), "application/json");
    }
    return send(404, "not found");
  }

  if (req.method === "POST") {
    if (!allowed()) return send(403, "forbidden");
    if (path !== "/new") return send(404, "not found");
    let pair: unknown;
    let svg: string;
    try {
      const out = await run(
        [T3, "auth", "pairing", "create", "--ttl", "5m", "--label", "pair-page", "--base-url", BASE_URL, "--json"],
        30,
      );
      pair = parseJson(out);
      svg = await run([QRENCODE, "-t", "SVG", "-m", "1", "-o", "-", String(key(pair, "pairUrl"))], 10);
    } catch (e) {
      if (!(e instanceof SubprocessError)) throw e;
      log(client, `mint failed: ${e.message}`);
      return send(502, "mint failed");
    }
    const body = {
      id: key(pair, "id"),
      url: key(pair, "pairUrl"),
      expiresAt: key(pair, "expiresAt"),
      svg,
    };
    return send(200, dumps(body), "application/json");
  }

  // http.server answers methods it has no handler for (HEAD included) with 501.
  const message = `Unsupported method ('${req.method}')`;
  const html =
    '<!DOCTYPE HTML>\n<html lang="en">\n    <head>\n        <meta charset="utf-8">\n' +
    "        <title>Error response</title>\n    </head>\n    <body>\n" +
    "        <h1>Error response</h1>\n        <p>Error code: 501</p>\n" +
    `        <p>Message: ${message}.</p>\n` +
    "        <p>Error code explanation: 501 - Server does not support this operation.</p>\n" +
    "    </body>\n</html>\n";
  log(client, `code 501, message ${message}`);
  return new Response(html, {
    status: 501,
    headers: { "Content-Type": "text/html;charset=utf-8", Connection: "close" },
  });
}

Bun.serve({
  hostname: "0.0.0.0",
  port: PORT,
  idleTimeout: 0, // minting can take longer than Bun's default 10 s
  async fetch(req, server) {
    const client = (server.requestIP(req)?.address ?? "-").replace(/^::ffff:/, "");
    const url = new URL(req.url);
    const path = url.pathname + url.search;
    const res = await handle(req, client, path);
    log(client, `"${req.method} ${path} HTTP/1.1" ${res.status} -`);
    return res;
  },
});
