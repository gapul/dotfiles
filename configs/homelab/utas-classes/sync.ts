#!/usr/bin/env bun
// Mirror the personal UTAS class calendar (.ics) into a Radicale collection.
//
// UTAS publishes one VEVENT per class meeting (room, [休]/[補] markers included)
// at a secret, unauthenticated URL that it rebuilds around 01:00 JST. Radicale
// cannot subscribe to a URL, so this copies the events in over CalDAV.
//
// Environment:
//     UTAS_ICS_URL       personal calendar URL from UTAS「カレンダー連携」
//     RADICALE_URL       collection URL, e.g. http://127.0.0.1:5232/gapul/cal-classes/
//     RADICALE_USER, RADICALE_PASSWORD
//     STATE_DIRECTORY    set by systemd; holds the hash of each event last written
//
// Only changed events are PUT, so clients do not resync everything daily.
// Future events missing from the feed are deleted (cancelled or moved); past
// ones are kept, because UTAS may drop a finished semester from the feed.
//
// Ported from sync.py. state.json keeps the format json.dumps wrote, so an existing state file
// carries over and no event is PUT again after the switch.
import { createHash } from "node:crypto";
import { existsSync, readFileSync, writeFileSync, writeSync } from "node:fs";
import { join } from "node:path";

const out = (line: string): void => void writeSync(1, `${line}\n`);
const err = (line: string): void => void writeSync(2, `${line}\n`);

function env(name: string): string {
  const value = process.env[name];
  if (value === undefined) throw new Error(`missing environment variable ${name}`);
  return value;
}

// UTAS uses TZID=Asia/Tokyo without defining it. Japan has no DST, so this is exact.
const VTIMEZONE = `BEGIN:VTIMEZONE
TZID:Asia/Tokyo
BEGIN:STANDARD
DTSTART:19700101T000000
TZOFFSETFROM:+0900
TZOFFSETTO:+0900
TZNAME:JST
END:STANDARD
END:VTIMEZONE`;

const MKCALENDAR_BODY = `<?xml version="1.0" encoding="utf-8"?>
<C:mkcalendar xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav" xmlns:I="http://apple.com/ns/ical/">
  <D:set><D:prop>
    <D:displayname>授業</D:displayname>
    <I:calendar-color>#34C759</I:calendar-color>
    <C:supported-calendar-component-set><C:comp name="VEVENT"/></C:supported-calendar-component-set>
  </D:prop></D:set>
</C:mkcalendar>`;

// Response bodies are decoded strictly, as bytes.decode() does; error bodies leniently.
const strict = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });
const lenient = new TextDecoder("utf-8", { ignoreBOM: true });

// urllib only follows redirects for GET, so CalDAV methods see the 3xx status themselves.
async function request(
  method: string,
  url: string,
  body: string | null = null,
  headers: Record<string, string> = {},
): Promise<[number, string]> {
  const auth = Buffer.from(`${env("RADICALE_USER")}:${env("RADICALE_PASSWORD")}`).toString("base64");
  const res = await fetch(url, {
    method,
    body,
    headers: { Authorization: `Basic ${auth}`, ...headers },
    redirect: method === "GET" ? "follow" : "manual",
    signal: AbortSignal.timeout(30_000),
  });
  const bytes = new Uint8Array(await res.arrayBuffer());
  return res.status >= 200 && res.status < 300 ? [res.status, strict.decode(bytes)] : [res.status, lenient.decode(bytes)];
}

// A Date for a floating JST wall time, or an error like strptime's for an impossible one.
function jst(stamp: string): Date {
  const [y, mo, d, h, mi, s] = [0, 4, 6, 9, 11, 13].map((i, n) => Number(stamp.slice(i, n === 0 ? 4 : i + 2)));
  const t = new Date(Date.UTC(y, mo - 1, d, h - 9, mi, s));
  const back = new Date(t.getTime() + 9 * 3600_000);
  if (back.getUTCFullYear() !== y || back.getUTCMonth() !== mo - 1 || back.getUTCDate() !== d || h > 23 || mi > 59 || s > 59) {
    throw new Error(`time data '${stamp}' does not match format '%Y%m%dT%H%M%S'`);
  }
  return t;
}

// datetime.isoformat() of a JST datetime: 2026-04-10T08:30:00+09:00
const jstIso = (t: Date): string => `${new Date(t.getTime() + 9 * 3600_000).toISOString().slice(0, 19)}+09:00`;

/** UID -> [VEVENT text, start]. Lines are unfolded first. */
function parseEvents(ics: string): Map<string, [string, Date | null]> {
  ics = ics.replaceAll("\r\n", "\n").replaceAll("\n ", "");
  const events = new Map<string, [string, Date | null]>();
  // Python's re.M: ^ and $ break at \n only (JS's m flag would also break at \r and U+2028).
  for (const [block] of ics.matchAll(/(?<=^|\n)BEGIN:VEVENT\n[\s\S]*?(?<=^|\n)END:VEVENT(?=\n|$)/g)) {
    const uidMatch = /(?<=^|\n)UID:([^\n]+)(?=\n|$)/.exec(block);
    if (!uidMatch) throw new Error(`VEVENT without UID:\n${block}`);
    const uid = uidMatch[1].trim();
    const start = /(?<=^|\n)DTSTART[^:]*:(\d{8}T\d{6})/.exec(block);
    events.set(uid, [block, start ? jst(start[1]) : null]);
  }
  return events;
}

// str.splitlines(): every line boundary Python knows, not just \n.
const splitlines = (s: string): string[] => {
  const lines = s.split(/\r\n|[\n\r\v\f\x1c\x1d\x1e\x85\u2028\u2029]/);
  if (lines.length > 1 && lines[lines.length - 1] === "") lines.pop();
  return s === "" ? [] : lines;
};

function eventHash(block: string): string {
  // DTSTAMP/LAST-MODIFIED change on every rebuild; leave them out of the hash.
  const stable = splitlines(block)
    .filter((line) => !line.startsWith("DTSTAMP") && !line.startsWith("LAST-MODIFIED"))
    .join("\n");
  return createHash("sha256").update(stable).digest("hex");
}

const hrefName = (uid: string): string => `${uid.replace(/[^A-Za-z0-9_-]/gu, "_")}.ics`;

// json.dumps(state): ", " / ": " separators and \uXXXX for anything outside printable ASCII.
function dumps(v: unknown): string {
  if (v === null || v === undefined) return "null";
  if (typeof v === "string") {
    return `"${v.replace(/[\\"\x00-\x1f\x7f-\uffff]/g, (c) => {
      const named: Record<string, string> = { '"': '\\"', "\\": "\\\\", "\n": "\\n", "\r": "\\r", "\t": "\\t", "\b": "\\b", "\f": "\\f" };
      return named[c] ?? `\\u${c.charCodeAt(0).toString(16).padStart(4, "0")}`;
    })}"`;
  }
  if (v instanceof Map || typeof v === "object") {
    return `{${(v instanceof Map ? [...v.entries()] : Object.entries(v as Record<string, unknown>))
      .map(([k, x]) => `${dumps(k)}: ${dumps(x)}`)
      .join(", ")}}`;
  }
  return String(v);
}

interface Entry {
  hash?: string;
  start?: string | null;
}

// state.json in file order. A plain object would hoist numeric-looking UIDs to the front, which
// reorders the file and the DELETEs; so every key gets a "_" prefix before JSON.parse sees it.
// (A JSON string followed by ':' is always a key.)
function loadState(text: string): Map<string, Entry> {
  const tagged = JSON.parse(text.replace(/"((?:[^"\\]|\\.)*)"(\s*:)/g, '"_$1"$2')) as Record<string, Record<string, string | null>>;
  return new Map(
    Object.entries(tagged).map(([uid, entry]) => [
      uid.slice(1),
      Object.fromEntries(Object.entries(entry).map(([k, v]) => [k.slice(1), v])) as Entry,
    ]),
  );
}

async function main(): Promise<number> {
  const base = `${env("RADICALE_URL").replace(/\/+$/, "")}/`;
  const statePath = join(process.env.STATE_DIRECTORY ?? ".", "state.json");
  let state = existsSync(statePath) ? loadState(readFileSync(statePath, "utf8")) : new Map<string, Entry>();

  const feed = await fetch(env("UTAS_ICS_URL"), { signal: AbortSignal.timeout(30_000) });
  if (!feed.ok) throw new Error(`HTTP Error ${feed.status}: ${feed.statusText}`);
  const events = parseEvents(strict.decode(new Uint8Array(await feed.arrayBuffer())));
  out(`feed: ${events.size} events`);

  let [status] = await request("PROPFIND", base, null, { Depth: "0" });
  if (status === 404) {
    let body: string;
    [status, body] = await request("MKCALENDAR", base, MKCALENDAR_BODY, { "Content-Type": "application/xml" });
    if (status !== 200 && status !== 201) {
      err(`error: MKCALENDAR ${status}: ${[...body].slice(0, 200).join("")}`);
      return 1;
    }
    out("created collection");
    state = new Map();
  }

  let put = 0;
  for (const [uid, [block, start]] of events) {
    const digest = eventHash(block);
    if (state.get(uid)?.hash === digest) continue;
    const body = `BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//gapul//utas-classes//JA\n${VTIMEZONE}\n${block}\nEND:VCALENDAR\n`;
    const [code, text] = await request("PUT", base + hrefName(uid), body.replaceAll("\n", "\r\n"), {
      "Content-Type": "text/calendar; charset=utf-8",
    });
    if (code !== 200 && code !== 201 && code !== 204) {
      err(`warning: PUT ${uid}: ${code}: ${[...text].slice(0, 200).join("")}`);
      continue;
    }
    state.set(uid, { hash: digest, start: start ? jstIso(start) : null });
    put += 1;
  }

  // An empty feed is more likely a UTAS hiccup than a semester with no classes.
  let deleted = 0;
  if (events.size) {
    const now = Date.now();
    for (const uid of [...state.keys()].filter((u) => !events.has(u))) {
      const start = state.get(uid)?.start;
      if (start && Date.parse(start) < now) continue;
      const [code] = await request("DELETE", base + hrefName(uid));
      if (code === 200 || code === 204 || code === 404) {
        state.delete(uid);
        deleted += 1;
      }
    }
  }

  writeFileSync(statePath, dumps(state));
  out(`put ${put}, deleted ${deleted}, tracked ${state.size}`);
  return 0;
}

process.exit(await main());
