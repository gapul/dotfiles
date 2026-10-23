// Regression tests for aac-matrix-approve.ts against a fake Matrix homeserver on localhost.
//
// The script hardcodes https://matrix.gapul.net and reads its token from ~/.config/ask, so it runs
// with HOME set to a temp dir and a --preload shim that rewrites the homeserver URL to the fake
// and rejects every other fetch. For the timeout case the shim also makes performance.now() jump
// a fixed step per call, so the 110 s deadline passes after two syncs.
import { afterAll, afterEach, beforeAll, expect, test } from "bun:test";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const SCRIPT = join(import.meta.dir, "aac-matrix-approve.ts");
const ROOM = "!SgoLc7XqTg7UqSDc0k_zjHYIZ3obMblRF68WZQKrZrU";
const ROOM_PATH = "%21SgoLc7XqTg7UqSDc0k_zjHYIZ3obMblRF68WZQKrZrU";
const APPROVER = "@gapul:gapul.net";
const BOT = "@aac-bot:gapul.net";

const SHIM = `
const map = JSON.parse(process.env.TEST_FETCH_MAP ?? "{}");
const realFetch = globalThis.fetch;
globalThis.fetch = (input, init) => {
  const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
  for (const [from, to] of Object.entries(map)) {
    if (url.startsWith(from)) return realFetch(to + url.slice(from.length), init);
  }
  return Promise.reject(new TypeError("blocked by test shim: " + url));
};
const step = Number(process.env.TEST_CLOCK_STEP_MS ?? "0");
if (step > 0) {
  // Whole steps from zero, so deadline arithmetic stays exact in floating point.
  let t = 0;
  performance.now = () => (t += step);
}
`;

type Json = any;
type Recorded = { method: string; path: string; auth: string | null; ua: string | null; body: string };

let root: string;
let shim: string;
let bunfig: string;
let server: ReturnType<typeof Bun.serve>;
let requests: Recorded[] = [];
let fake: {
  whoami: string;
  whoamiStatus: number;
  batches: Json[][];
  failNotice: boolean;
} = { whoami: BOT, whoamiStatus: 200, batches: [], failNotice: false };
let messageCount = 0;
let reactionCount = 0;

beforeAll(() => {
  root = mkdtempSync(join(tmpdir(), "aac-approve-test-"));
  shim = join(root, "shim.js");
  writeFileSync(shim, SHIM);
  bunfig = join(root, "bunfig.toml");
  writeFileSync(bunfig, "");
  server = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    async fetch(req) {
      const url = new URL(req.url);
      const path = url.pathname + url.search;
      requests.push({
        method: req.method,
        path,
        auth: req.headers.get("authorization"),
        ua: req.headers.get("user-agent"),
        body: await req.text(),
      });
      const base = "/_matrix/client/v3";
      if (url.pathname === `${base}/account/whoami`) {
        if (fake.whoamiStatus !== 200) return new Response("nope", { status: fake.whoamiStatus });
        return Response.json({ user_id: fake.whoami });
      }
      if (url.pathname === `${base}/sync`) {
        const since = url.searchParams.get("since");
        if (since === null) return Response.json({ next_batch: "s0" });
        const n = Number(since.slice(1));
        const events = fake.batches[n] ?? [];
        return Response.json({
          next_batch: `s${n + 1}`,
          rooms: { join: { [ROOM]: { timeline: { events } } } },
        });
      }
      const send = /^\/_matrix\/client\/v3\/rooms\/[^/]+\/send\/([^/]+)\/[^/]+$/.exec(url.pathname);
      if (send && req.method === "PUT") {
        if (send[1] === "m.reaction") return Response.json({ event_id: `$r${++reactionCount}` });
        messageCount++;
        if (messageCount === 1) return Response.json({ event_id: "$q1" });
        if (fake.failNotice) return new Response("down", { status: 500 });
        return Response.json({ event_id: "$notice" });
      }
      return new Response("not found", { status: 404 });
    },
  });
});

afterAll(() => {
  server.stop(true);
  rmSync(root, { recursive: true, force: true });
});

afterEach(() => {
  requests = [];
  fake = { whoami: BOT, whoamiStatus: 200, batches: [], failNotice: false };
  messageCount = 0;
  reactionCount = 0;
});

let homeSeq = 0;

async function run(
  env: Record<string, string>,
  opts: { token?: string | null; clockStepMs?: number } = {},
): Promise<{ code: number; stdout: string; stderr: string; log: string[] }> {
  const home = join(root, `home${homeSeq++}`);
  mkdirSync(home, { recursive: true });
  if (opts.token !== null) {
    mkdirSync(join(home, ".config/ask"), { recursive: true });
    writeFileSync(join(home, ".config/ask/matrix-token"), `${opts.token ?? "tok-123"}\n`);
  }
  const proc = Bun.spawn(
    [process.execPath, "--no-env-file", `--config=${bunfig}`, "--no-install", "--preload", shim, SCRIPT],
    {
      cwd: root,
      env: {
        HOME: home,
        PATH: process.env.PATH ?? "/usr/bin:/bin",
        TEST_FETCH_MAP: JSON.stringify({ "https://matrix.gapul.net": `http://127.0.0.1:${server.port}` }),
        TEST_CLOCK_STEP_MS: String(opts.clockStepMs ?? 0),
        ...env,
      },
      stdout: "pipe",
      stderr: "pipe",
    },
  );
  const [code, stdout, stderr] = await Promise.all([
    proc.exited,
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  const logFile = join(home, ".local/state/aac/approve.log");
  const log = existsSync(logFile)
    ? readFileSync(logFile, "utf8")
        .split("\n")
        .filter(Boolean)
        .map((line) => {
          expect(line).toMatch(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d /);
          return line.slice(20);
        })
    : [];
  return { code, stdout, stderr, log };
}

const reaction = (sender: string, eventId: string, key: string) => ({
  type: "m.reaction",
  sender,
  content: { "m.relates_to": { rel_type: "m.annotation", event_id: eventId, key } },
});

const message = (sender: string, body: string, inReplyTo?: string) => ({
  type: "m.room.message",
  sender,
  content: {
    msgtype: "m.text",
    body,
    ...(inReplyTo ? { "m.relates_to": { "m.in_reply_to": { event_id: inReplyTo } } } : {}),
  },
});

const sends = (type: string) =>
  requests.filter((r) => r.method === "PUT" && r.path.includes(`/send/${type}/`));

function syncQuery(r: Recorded): { timeout: string | null; since: string | null; filter: Json } {
  const q = new URL(`http://x${r.path}`).searchParams;
  return { timeout: q.get("timeout"), since: q.get("since"), filter: JSON.parse(q.get("filter") ?? "null") };
}

const BASE_ENV = { AAC_DOMAIN: "example.com", AAC_DEVICE: "laptop", AAC_USERNAME: "alice" };

test("single credential: approver's ✅ approves with exit 0 and the exact request sequence", async () => {
  fake.batches = [[reaction(APPROVER, "$q1", "✅")]];
  const r = await run(BASE_ENV);
  expect(r.code).toBe(0);
  expect(r.stdout).toBe("");

  const kinds = requests.map((q) => `${q.method} ${q.path.split("?")[0].replace(/\/[0-9a-f]{32}$/, "/TXN")}`);
  const send = (t: string) => `PUT /_matrix/client/v3/rooms/${ROOM_PATH}/send/${t}/TXN`;
  expect(kinds).toEqual([
    "GET /_matrix/client/v3/account/whoami",
    "GET /_matrix/client/v3/sync",
    send("m.room.message"),
    send("m.reaction"),
    send("m.reaction"),
    "GET /_matrix/client/v3/sync",
    send("m.room.message"),
  ]);
  for (const q of requests) {
    expect(q.auth).toBe("Bearer tok-123");
    expect(q.ua).toBe("aac-matrix-approve");
  }

  // Sync position is taken before posting, then long-polled from there.
  const first = syncQuery(requests[1]);
  expect(first).toEqual({
    timeout: "0",
    since: null,
    filter: { room: { rooms: [ROOM], timeline: { limit: 50 } } },
  });
  // Bodies are json.dumps-shaped: ", " / ": " separators, non-ASCII escaped.
  expect(requests[1].path).toContain(
    "filter=%7B%22room%22%3A+%7B%22rooms%22%3A+%5B%22%21SgoLc7XqTg7UqSDc0k_zjHYIZ3obMblRF68WZQKrZrU%22%5D",
  );
  const second = syncQuery(requests[5]);
  expect(second.since).toBe("s0");
  expect(second.timeout).toBe("20000");

  expect(requests[2].body).toBe(
    '{"msgtype": "m.text", "body": "[aac] Send the credential for example.com (alice) to laptop?\\ntap \\u2705 / \\u274c"}',
  );
  expect(requests[3].body).toBe(
    '{"m.relates_to": {"rel_type": "m.annotation", "event_id": "$q1", "key": "\\u2705"}}',
  );
  expect(JSON.parse(requests[4].body)["m.relates_to"].key).toBe("❌");
  expect(JSON.parse(requests[6].body)).toEqual({
    msgtype: "m.notice",
    body: "[aac] example.com: approved",
    "m.relates_to": { "m.in_reply_to": { event_id: "$q1" } },
  });
  // Every send uses a fresh transaction id.
  const txns = sends("m.room.message").concat(sends("m.reaction")).map((q) => q.path.split("/").pop());
  expect(new Set(txns).size).toBe(4);

  expect(r.log).toEqual(["asked $q1 domain=example.com device=laptop candidates=0", "approved $q1"]);
});

test("no username: the question omits the parenthesis", async () => {
  fake.batches = [[reaction(APPROVER, "$q1", "✅")]];
  const r = await run({ AAC_DOMAIN: "example.com", AAC_DEVICE: "laptop" });
  expect(r.code).toBe(0);
  expect(JSON.parse(sends("m.room.message")[0].body).body).toBe(
    "[aac] Send the credential for example.com to laptop?\ntap ✅ / ❌",
  );
});

test("❌ denies with exit 1 and a 'denied' notice", async () => {
  fake.batches = [[reaction(APPROVER, "$q1", "❌")]];
  const r = await run(BASE_ENV);
  expect(r.code).toBe(1);
  expect(r.stdout).toBe("");
  expect(JSON.parse(sends("m.room.message")[1].body).body).toBe("[aac] example.com: denied");
  expect(r.log).toEqual(["asked $q1 domain=example.com device=laptop candidates=0", "denied $q1"]);
});

test("ignores the bot's own buttons, other senders, other events and plain numbers", async () => {
  fake.batches = [
    [
      reaction(BOT, "$q1", "✅"),
      reaction("@mallory:gapul.net", "$q1", "✅"),
      reaction(APPROVER, "$other", "✅"),
      reaction(APPROVER, "$q1", "👍"),
      message(APPROVER, "1"),
    ],
    [message(BOT, "yes"), reaction(APPROVER, "$q1", "❌")],
  ];
  const r = await run(BASE_ENV);
  expect(r.code).toBe(1);
  const syncs = requests.filter((q) => q.path.startsWith("/_matrix/client/v3/sync"));
  expect(syncs.map((q) => syncQuery(q).since)).toEqual([null, "s0", "s1"]);
  expect(r.log.at(-1)).toBe("denied $q1");
});

const CANDIDATES = [
  { name: "Personal", username: "alice", uri: "https://Login.Example.com:8443/path?x=1" },
  { name: "Work", username: "", uri: "example.com" },
  { name: "", username: "bob", uri: null },
];

test("candidates: keycap buttons, U+FE0F-less reaction picks the number on stdout", async () => {
  fake.batches = [[reaction(APPROVER, "$q1", "2\u20E3")]];
  const r = await run({ ...BASE_ENV, AAC_CANDIDATES: JSON.stringify(CANDIDATES) });
  expect(r.code).toBe(0);
  expect(r.stdout).toBe("2\n");

  const msgs = sends("m.room.message");
  expect(JSON.parse(msgs[0].body).body).toBe(
    [
      "[aac] 3 credentials match example.com. Which one goes to laptop?",
      "  1. Personal — alice (login.example.com)",
      "  2. Work — no username (example.com)",
      "  3. ? — bob (?)",
      "tap a number, or ❌ to deny",
    ].join("\n"),
  );
  expect(sends("m.reaction").map((q) => JSON.parse(q.body)["m.relates_to"].key)).toEqual([
    "1\uFE0F\u20E3",
    "2\uFE0F\u20E3",
    "3\uFE0F\u20E3",
    "❌",
  ]);
  expect(JSON.parse(msgs[1].body).body).toBe("[aac] example.com: approved #2 (Work)");
  expect(r.log).toEqual([
    "asked $q1 domain=example.com device=laptop candidates=3",
    "approved #2 (Work) $q1",
  ]);
});

test("candidates: a reply with a fullwidth digit counts; out-of-range and foreign replies do not", async () => {
  fake.batches = [
    [
      message(APPROVER, "> quoted\n1", "$other"),
      message(APPROVER, "4", "$q1"),
      message(APPROVER, "0"),
      message(APPROVER, "two"),
      message(APPROVER, "> <@aac-bot:gapul.net> [aac] 3 credentials...\n\n３", "$q1"),
    ],
  ];
  const r = await run({ ...BASE_ENV, AAC_CANDIDATES: JSON.stringify(CANDIDATES) });
  expect(r.code).toBe(0);
  // The answer text goes out as typed (Python printed it the same way).
  // aac gets the number in ASCII.
  expect(r.stdout).toBe("3\n");
  expect(r.log.at(-1)).toBe("approved #3 () $q1");
});

test("candidates: a plain (non-reply) number message picks that candidate", async () => {
  fake.batches = [[message(APPROVER, " 1 ")]];
  const r = await run({ ...BASE_ENV, AAC_CANDIDATES: JSON.stringify(CANDIDATES) });
  expect(r.code).toBe(0);
  expect(r.stdout).toBe("1\n");
  expect(JSON.parse(sends("m.room.message")[1].body).body).toBe("[aac] example.com: approved #1 (Personal)");
});

test("more than nine candidates: nine keycaps plus ❌, and the text asks for a number", async () => {
  const many = Array.from({ length: 12 }, (_, i) => ({ name: `n${i + 1}`, username: "u", uri: "h" }));
  fake.batches = [[message(APPROVER, "12")]];
  const r = await run({ ...BASE_ENV, AAC_CANDIDATES: JSON.stringify(many) });
  expect(r.code).toBe(0);
  expect(r.stdout).toBe("12\n");
  const keys = sends("m.reaction").map((q) => JSON.parse(q.body)["m.relates_to"].key);
  expect(keys).toHaveLength(10);
  expect(keys.at(-1)).toBe("❌");
  expect(keys[8]).toBe("9\uFE0F\u20E3");
  const text: string = JSON.parse(sends("m.room.message")[0].body).body;
  expect(text.split("\n").at(-1)).toBe("tap 1–9 or send the number, or ❌ to deny");
  expect(r.log.at(-1)).toBe("approved #12 (n12) $q1");
});

test("more than 30 candidates are denied before touching Matrix", async () => {
  const many = Array.from({ length: 31 }, (_, i) => ({ name: `n${i}` }));
  const r = await run({ ...BASE_ENV, AAC_CANDIDATES: JSON.stringify(many) });
  expect(r.code).toBe(1);
  expect(r.stdout).toBe("");
  expect(requests).toEqual([]);
  expect(r.log).toEqual(["denied: 31 candidates for example.com, more than 30"]);
});

test("an empty candidate list is denied too", async () => {
  const r = await run({ ...BASE_ENV, AAC_CANDIDATES: "[]" });
  expect(r.code).toBe(1);
  expect(requests).toEqual([]);
  expect(r.log).toEqual(["denied: no candidates for example.com"]);
});

test("refuses when the bot token belongs to the approver", async () => {
  fake.whoami = APPROVER;
  const r = await run(BASE_ENV);
  expect(r.code).toBe(1);
  expect(requests.map((q) => q.path)).toEqual(["/_matrix/client/v3/account/whoami"]);
  expect(r.log).toEqual(["refused: bot token is the approver's account"]);
});

test("timeout: no answer before the deadline exits 1 with a 'timed out' notice", async () => {
  // Each performance.now() call advances 50 s: deadline = t1 + 110, then left = 60, 10, -40.
  const r = await run(BASE_ENV, { clockStepMs: 50_000 });
  expect(r.code).toBe(1);
  const polls = requests
    .filter((q) => q.path.startsWith("/_matrix/client/v3/sync"))
    .map(syncQuery)
    .slice(1);
  expect(polls.map((p) => [p.since, p.timeout])).toEqual([
    ["s0", "20000"],
    ["s1", "10000"],
  ]);
  expect(JSON.parse(sends("m.room.message")[1].body).body).toBe("[aac] example.com: timed out");
  expect(r.log).toEqual(["asked $q1 domain=example.com device=laptop candidates=0", "timed out $q1"]);
});

test("an HTTP error from the homeserver is logged Python-style and exits 1", async () => {
  fake.whoamiStatus = 500;
  const r = await run(BASE_ENV);
  expect(r.code).toBe(1);
  expect(r.log).toEqual(["error: <HTTPError 500: 'Internal Server Error'>"]);
});

test("a missing token file exits 1 without any request", async () => {
  const r = await run(BASE_ENV, { token: null });
  expect(r.code).toBe(1);
  expect(requests).toEqual([]);
  expect(r.log).toEqual(["error: FileNotFoundError(2, 'No such file or directory')"]);
});

test("a failed notice does not undo the approval", async () => {
  fake.batches = [[reaction(APPROVER, "$q1", "✅")]];
  fake.failNotice = true;
  const r = await run(BASE_ENV);
  expect(r.code).toBe(0);
  expect(r.log).toEqual([
    "asked $q1 domain=example.com device=laptop candidates=0",
    "approved $q1",
    "notice failed: HTTP Error 500: Internal Server Error",
  ]);
});
