#!/usr/bin/env bun
// Approve one `aac listen` credential request from Matrix.
//
// Run by the patched `aac listen` (AAC_APPROVAL_COMMAND) with AAC_DOMAIN, AAC_DEVICE and
// AAC_USERNAME set. Posts the question into the ask broker's approval room with ✅ / ❌ reactions as
// buttons and exits 0 only when the approver taps ✅. Everything else — ❌, a timeout, a Matrix
// error — exits 1, which aac reads as a denial.
//
// When several vault items match, aac sets AAC_CANDIDATES instead (a JSON list of name / username /
// uri, no secrets). The buttons are then 1️⃣…9️⃣ and ❌, and a Matrix reply to the question with a
// number works too (the only way past nine), as does a plain message holding just the number: aac
// asks one question at a time and only messages after this one are read, so it cannot answer another. The chosen number goes to stdout with exit 0, which aac
// reads as "send that one".
//
// The bot token is readable by the agents, so the answer only counts when it comes from the
// approver's own account, as a reaction to this exact message. The bot's own reactions (the buttons)
// are ignored, and the bot must not be the approver.
//
// Ported from aac-matrix-approve.py: same requests, log lines, stdout and exit codes.
import { appendFileSync, mkdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname } from "node:path";

const HOMESERVER = "https://matrix.gapul.net";
const ROOM = "!SgoLc7XqTg7UqSDc0k_zjHYIZ3obMblRF68WZQKrZrU";
const TOKEN_FILE = `${homedir()}/.config/ask/matrix-token`;
const APPROVER = "@gapul:gapul.net";
// `aac run` gives up after 120 s by default; answer (as a denial) before it does.
const TIMEOUT_SECONDS = 110;
const LOG = `${homedir()}/.local/state/aac/approve.log`;

const YES = "✅";
const NO = "❌";
// Past this a list is no use on a phone; narrow the search or ask by --id.
const MAX_CANDIDATES = 30;
// Keycap emoji for candidates. Clients differ on the U+FE0F variation selector, so keys are
// compared with it stripped.
const KEYCAPS = Array.from({ length: 9 }, (_, i) => `${i + 1}\uFE0F\u20E3`);

type Json = any; // Matrix events and aac's candidates are untyped JSON
type Candidate = { name?: string; username?: string; uri?: string };

const bare = (key: string): string => key.replaceAll("\uFE0F", "");

function log(message: string): void {
  mkdirSync(dirname(LOG), { recursive: true });
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, "0");
  const now = `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
  appendFileSync(LOG, `${now} ${message}\n`);
}

// json.dumps with its defaults (ASCII only, ", " / ": " separators)
function dumps(v: Json): string {
  if (v === null || v === undefined) return "null";
  if (typeof v === "string" || typeof v === "number" || typeof v === "boolean") {
    return JSON.stringify(v).replace(
      /[\u007f-\uffff]/g,
      (c) => `\\u${c.charCodeAt(0).toString(16).padStart(4, "0")}`,
    );
  }
  if (Array.isArray(v)) return `[${v.map(dumps).join(", ")}]`;
  return `{${Object.entries(v)
    .map(([k, x]) => `${dumps(k)}: ${dumps(x)}`)
    .join(", ")}}`;
}

// urllib.parse.quote(s) (safe="/") and urlencode (quote_plus)
const pct = (c: string) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`;
const quote = (s: string): string =>
  encodeURIComponent(s).replace(/[!'()*]/g, pct).replace(/%2F/g, "/");
const urlencode = (q: Record<string, string>): string =>
  Object.entries(q)
    .map(
      ([k, v]) =>
        `${encodeURIComponent(k).replace(/[!'()*]/g, pct).replace(/%20/g, "+")}=${encodeURIComponent(v).replace(/[!'()*]/g, pct).replace(/%20/g, "+")}`,
    )
    .join("&");

// An exception that already carries its Python repr, for the log.
class PyError extends Error {
  constructor(readonly repr: string) {
    super(repr);
  }
}

function reprOf(exc: unknown): string {
  if (exc instanceof PyError) return exc.repr;
  if (exc instanceof HTTPError) return exc.repr();
  const e = exc as { name?: string; code?: string; message?: string };
  if (e?.code === "ENOENT") return "FileNotFoundError(2, 'No such file or directory')";
  if (e?.code === "EACCES") return "PermissionError(13, 'Permission denied')";
  if (e?.name === "TimeoutError") return "TimeoutError('timed out')";
  if (e?.code === "ConnectionRefused") return "URLError(ConnectionRefusedError(61, 'Connection refused'))";
  if (e instanceof SyntaxError) return `JSONDecodeError('${e.message}')`;
  return `${e?.name ?? "Exception"}('${e?.message ?? String(exc)}')`;
}

// d[k] with Python's KeyError
function K(d: Json, k: string): Json {
  if (d === null || typeof d !== "object" || !(k in d)) throw new PyError(`KeyError('${k}')`);
  return d[k];
}

// An HTTP error worded like urllib's HTTPError, for the log.
class HTTPError extends Error {
  constructor(
    readonly code: number,
    readonly reason: string,
  ) {
    super(`HTTP Error ${code}: ${reason}`);
  }
  repr(): string {
    return `<HTTPError ${this.code}: '${this.reason}'>`;
  }
}

async function call(
  token: string,
  method: string,
  path: string,
  body: Json = null,
  timeout = 30,
): Promise<Json> {
  const res = await fetch(`${HOMESERVER}/_matrix/client/v3${path}`, {
    method,
    body: body === null ? undefined : dumps(body),
    // A bare default User-Agent gets a 403 from the proxy in front of matrix.gapul.net.
    headers: {
      Authorization: `Bearer ${token}`,
      "User-Agent": "aac-matrix-approve",
      "Content-Type": "application/json",
    },
    signal: AbortSignal.timeout(timeout * 1000),
  });
  if (res.status < 200 || res.status >= 300) throw new HTTPError(res.status, res.statusText);
  return JSON.parse(await res.text());
}

async function send(token: string, eventType: string, content: Json): Promise<string> {
  const room = quote(ROOM);
  const txn = crypto.randomUUID().replaceAll("-", "");
  const path = `/rooms/${room}/send/${eventType}/${txn}`;
  const res = await call(token, "PUT", path, content);
  return K(res, "event_id");
}

async function sync(token: string, since: string | null, timeoutMs: number): Promise<Json> {
  const roomFilter = dumps({ room: { rooms: [ROOM], timeline: { limit: 50 } } });
  const query: Record<string, string> = { timeout: String(timeoutMs), filter: roomFilter };
  if (since) query.since = since;
  return call(token, "GET", `/sync?${urlencode(query)}`, null, Math.floor(timeoutMs / 1000) + 30);
}

// str.isdigit() / int() on what a phone keyboard can send: any decimal digits, fullwidth included.
// isdigit() also takes superscripts and circled digits, which int() then refuses.
const ISDIGIT =
  /^[\p{Nd}\u{B2}-\u{B3}\u{B9}\u{1369}-\u{1371}\u{19DA}\u{2070}\u{2074}-\u{2079}\u{2080}-\u{2089}\u{2460}-\u{2468}\u{2474}-\u{247C}\u{2488}-\u{2490}\u{24EA}\u{24F5}-\u{24FD}\u{24FF}\u{2776}-\u{277E}\u{2780}-\u{2788}\u{278A}-\u{2792}\u{10A40}-\u{10A43}\u{10E60}-\u{10E68}\u{11052}-\u{1105A}\u{1F100}-\u{1F10A}]+$/u;
// The zero of every block of decimal digits (Unicode 15.1, as in Python 3.13's unicodedata).
const ZEROS = [
  0x30, 0x660, 0x6f0, 0x7c0, 0x966, 0x9e6, 0xa66, 0xae6, 0xb66, 0xbe6, 0xc66, 0xce6, 0xd66, 0xde6,
  0xe50, 0xed0, 0xf20, 0x1040, 0x1090, 0x17e0, 0x1810, 0x1946, 0x19d0, 0x1a80, 0x1a90, 0x1b50,
  0x1bb0, 0x1c40, 0x1c50, 0xa620, 0xa8d0, 0xa900, 0xa9d0, 0xa9f0, 0xaa50, 0xabf0, 0xff10, 0x104a0,
  0x10d30, 0x11066, 0x110f0, 0x11136, 0x111d0, 0x112f0, 0x11450, 0x114d0, 0x11650, 0x116c0, 0x11730,
  0x118e0, 0x11950, 0x11c50, 0x11d50, 0x11da0, 0x11f50, 0x16a60, 0x16ac0, 0x16b50, 0x1d7ce, 0x1d7d8,
  0x1d7e2, 0x1d7ec, 0x1d7f6, 0x1e140, 0x1e2f0, 0x1e4f0, 0x1e950, 0x1fbf0,
];

function int(text: string): number {
  let n = 0;
  for (const ch of text) {
    const cp = ch.codePointAt(0) ?? 0;
    const zero = ZEROS.findLast((z) => z <= cp) ?? 0;
    if (!/\p{Nd}/u.test(ch) || cp - zero > 9) {
      throw new PyError(`ValueError("invalid literal for int() with base 10: '${text}'")`);
    }
    n = n * 10 + (cp - zero);
  }
  return n;
}

/** The approver's answer to `posted`: a reaction mapped through `buttons` (bare key → answer),
 * or, when there are `choices`, a number from 1 to `choices` in a reply to it or a plain message
 * (one that replies to some other message does not count). */
function answerIn(
  batch: Json,
  posted: string,
  buttons: Map<string, string>,
  choices = 0,
): string | null {
  const events: Json[] = batch?.rooms?.join?.[ROOM]?.timeline?.events ?? [];
  for (const event of events) {
    if (event?.sender !== APPROVER) continue;
    const content = event.content ?? {};
    const relates = content["m.relates_to"] || {};
    if (event.type === "m.reaction") {
      if (relates.event_id !== posted) continue;
      const answer = buttons.get(bare(relates.key ?? ""));
      if (answer !== undefined) return answer;
    } else if (event.type === "m.room.message" && choices) {
      const replied = (relates["m.in_reply_to"] || {}).event_id ?? null;
      if (replied !== null && replied !== posted) continue;
      // A reply body quotes the original as "> " lines first.
      const text = String(content.body ?? "")
        .split(/\r\n|[\n\r\v\f\x1c-\x1e\x85\u2028\u2029]/)
        .filter((line) => !line.startsWith(">"))
        .join("\n")
        .trim();
      // Normalised to ASCII: the approver may type fullwidth digits, and aac reads stdout as a number.
      if (ISDIGIT.test(text) && 1 <= int(text) && int(text) <= choices) return String(int(text));
    }
  }
  return null;
}

// urllib.parse.urlsplit(uri).hostname, or the uri itself
function host(uri: string | null | undefined): string {
  let rest = (uri || "").trim();
  const colon = rest.indexOf(":");
  if (colon > 0 && /^[A-Za-z][A-Za-z0-9+.-]*$/.test(rest.slice(0, colon))) rest = rest.slice(colon + 1);
  let hostname: string | null = null;
  if (rest.startsWith("//")) {
    const netloc = rest.slice(2).split(/[/?#]/)[0];
    const hostinfo = netloc.slice(netloc.lastIndexOf("@") + 1);
    const h = hostinfo.includes("[")
      ? (hostinfo.split("[")[1] ?? "").split("]")[0]
      : hostinfo.split(":")[0];
    hostname = h ? h.toLowerCase() : null;
  }
  return hostname || uri || "?";
}

/** Message text and buttons (key → answer, in display order). */
function question(
  domain: string,
  device: string,
  username: string,
  candidates: Candidate[] | null,
): [string, Map<string, string>] {
  if (candidates === null) {
    const who = username ? ` (${username})` : "";
    const text = `[aac] Send the credential for ${domain}${who} to ${device}?\ntap ${YES} / ${NO}`;
    return [
      text,
      new Map([
        [YES, "yes"],
        [NO, "no"],
      ]),
    ];
  }
  const lines = candidates.map(
    (c, i) =>
      `  ${i + 1}. ${c.name || "?"} — ${c.username || "no username"} (${host(c.uri)})`,
  );
  let text = [
    `[aac] ${candidates.length} credentials match ${domain}. Which one goes to ${device}?`,
    ...lines,
    `tap a number, or ${NO} to deny`,
  ].join("\n");
  if (candidates.length > KEYCAPS.length) {
    text = text.replaceAll("tap a number", `tap 1–${KEYCAPS.length} or send the number`);
  }
  const buttons = new Map<string, string>();
  for (let i = 0; i < Math.min(candidates.length, KEYCAPS.length); i++) {
    buttons.set(KEYCAPS[i], String(i + 1));
  }
  buttons.set(NO, "no");
  return [text, buttons];
}

async function main(): Promise<number> {
  const domain = process.env.AAC_DOMAIN ?? "?";
  const device = process.env.AAC_DEVICE ?? "?";
  const username = process.env.AAC_USERNAME ?? "";
  const raw = process.env.AAC_CANDIDATES;
  const candidates: Candidate[] | null = raw ? JSON.parse(raw) : null;
  if (candidates !== null && !(candidates.length >= 1 && candidates.length <= MAX_CANDIDATES)) {
    log(
      candidates.length === 0
        ? `denied: no candidates for ${domain}`
        : `denied: ${candidates.length} candidates for ${domain}, more than ${MAX_CANDIDATES}`,
    );
    return 1;
  }
  const token = readFileSync(TOKEN_FILE, "utf8").trim();

  if ((await call(token, "GET", "/account/whoami")).user_id === APPROVER) {
    log("refused: bot token is the approver's account");
    return 1;
  }

  // Take the sync position before posting, so a fast tap cannot land before it.
  let since: string = K(await sync(token, null, 0), "next_batch");
  const [text, buttons] = question(domain, device, username, candidates);
  const posted = await send(token, "m.room.message", { msgtype: "m.text", body: text });
  for (const key of buttons.keys()) {
    await send(token, "m.reaction", {
      "m.relates_to": { rel_type: "m.annotation", event_id: posted, key },
    });
  }
  log(`asked ${posted} domain=${domain} device=${device} candidates=${(candidates ?? []).length}`);

  const byKey = new Map([...buttons].map(([k, v]) => [bare(k), v]));
  const deadline = performance.now() / 1000 + TIMEOUT_SECONDS;
  let answer: string | null = null;
  let left: number;
  while (answer === null && (left = deadline - performance.now() / 1000) > 0) {
    const batch = await sync(token, since, Math.floor(Math.min(left, 20) * 1000));
    since = K(batch, "next_batch");
    answer = answerIn(batch, posted, byKey, (candidates ?? []).length);
  }

  let outcome: string;
  if (answer === null) outcome = "timed out";
  else if (answer === "no") outcome = "denied";
  else if (candidates === null) outcome = "approved";
  else outcome = `approved #${answer} (${candidates[int(answer) - 1].name ?? "None"})`;
  log(`${outcome} ${posted}`);
  try {
    await send(token, "m.room.message", {
      msgtype: "m.notice",
      body: `[aac] ${domain}: ${outcome}`,
      "m.relates_to": { "m.in_reply_to": { event_id: posted } },
    });
  } catch (exc) {
    // the answer still stands
    log(`notice failed: ${(exc as Error).message}`);
  }

  if (answer === null || answer === "no") return 1;
  if (candidates !== null) process.stdout.write(`${answer}\n`);
  return 0;
}

try {
  process.exitCode = await main();
} catch (exc) {
  log(`error: ${reprOf(exc)}`);
  process.exitCode = 1;
}
