// Regression tests for receiver.ts: the HTTP contract and the SQLite rows it writes.
// The receiver runs as a subprocess on an ephemeral loopback port with a temp DB.
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { Database } from "bun:sqlite";
import { existsSync, mkdtempSync, rmSync } from "node:fs";
import { connect } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { gzipSync } from "node:zlib";

const SCRIPT = join(import.meta.dir, "receiver.ts");
const TOKEN = "s3cret-token";
const DEFAULT_USER = "5ea4d000-0000-4000-8000-000000000001";
const U = (n: number): string => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const W1 = U(900);

type Server = { proc: Bun.Subprocess<"ignore", "pipe", "pipe">; port: number; stderr: () => string };

function receiverEnv(dir: string, extra: Record<string, string> = {}): Record<string, string> {
  return { PATH: process.env.PATH ?? "/usr/bin:/bin", HOME: dir, PULS_TOKEN: TOKEN, PULS_DB: join(dir, "puls.sqlite"), PULS_PORT: "0", ...extra };
}

async function startServer(dir: string): Promise<Server> {
  const proc = Bun.spawn([process.execPath, "--no-env-file", SCRIPT], {
    cwd: dir,
    env: receiverEnv(dir),
    stdin: "ignore",
    stdout: "pipe",
    stderr: "pipe",
  });
  let errText = "";
  void (async () => {
    for await (const chunk of proc.stderr) errText += new TextDecoder().decode(chunk);
  })();
  const reader = proc.stdout.getReader();
  let outText = "";
  const deadline = Date.now() + 10_000;
  while (!/listening on 127\.0\.0\.1:\d+\n/.test(outText)) {
    if (Date.now() > deadline) throw new Error(`receiver did not start: ${outText} ${errText}`);
    const { value, done } = await reader.read();
    if (done) throw new Error(`receiver exited: ${outText} ${errText}`);
    outText += new TextDecoder().decode(value);
  }
  reader.releaseLock();
  const m = /^puls-sqlite-receiver listening on 127\.0\.0\.1:(\d+)\n$/.exec(outText);
  if (!m) throw new Error(`unexpected banner: ${outText}`);
  return { proc, port: Number(m[1]), stderr: () => errText };
}

const nd = (...lines: (string | object)[]): string =>
  lines.map((l) => (typeof l === "string" ? l : JSON.stringify(l))).join("\n") + "\n";

const hdr = (bid: number, extra: Record<string, unknown> = {}): Record<string, unknown> => ({
  batchID: U(bid),
  type: "delta",
  deviceID: "dev-1",
  reason: "bg",
  schemaVersion: 1,
  clientVersion: "1.2",
  exportedAt: 1760000000123.5,
  ...extra,
});

// Bun re-escapes non-ASCII inside String.raw templates, so it is interpolated.
const NAME = "川島のApple Watch 😀";
// Raw lines keep the float spellings (72.0, 3.0, 1E3) that JSON.stringify would lose.
const SAMPLE1 = String.raw`{"uuid":"${U(1)}","type":"HKQuantityTypeIdentifierHeartRate","kind":"quantity","start":1760000000000,"end":1760000001000.0,"value":72.0,"unit":"count/min","sourceName":"${NAME}","device":"Watch7,1","extra":{"a":[1,2.50,1e-5,1.5e16,123456789012345678.0,-0.0,1E3]}}`;
// json.dumps(ensure_ascii=True) escapes non-ASCII as \\uXXXX (BS avoids escapes in this source).
const BS = "\\";
const SAMPLE1_STORED = String.raw`{"uuid":"${U(1)}","type":"HKQuantityTypeIdentifierHeartRate","kind":"quantity","start":1760000000000,"end":1760000001000.0,"value":72.0,"unit":"count/min","sourceName":"${BS}u5ddd${BS}u5cf6${BS}u306eApple Watch ${BS}ud83d${BS}ude00","device":"Watch7,1","extra":{"a":[1,2.5,1e-05,1.5e+16,1.2345678901234568e+17,-0.0,1000.0]}}`;
const SAMPLE2 = String.raw`{"uuid": "${U(2)}", "type": "HKCategoryTypeIdentifierSleepAnalysis", "kind": "category", "start": 1760000000000, "category": 3.0, "sourceName": "Tab\there\u007f\"q\"\\"}`;
const SAMPLE2_STORED = String.raw`{"uuid":"${U(2)}","type":"HKCategoryTypeIdentifierSleepAnalysis","kind":"category","start":1760000000000,"category":3.0,"sourceName":"Tab\there\u007f\"q\"\\"}`;

const FULL = nd(
  hdr(1, {
    sampleCount: 4,
    deletionCount: 1,
    routeCount: 1,
    seriesCount: 1,
    aggregateCount: 2,
    activitySummaryCount: 2,
    profileCount: 1,
  }),
  SAMPLE1,
  SAMPLE2,
  { uuid: W1, type: "HKWorkoutTypeIdentifier", kind: "workout", start: 1760000000000, end: 1760003600000, workout: { activity: 37 } },
  { uuid: U(4), type: "Mood", kind: "stateOfMind", start: -1500.5, stateOfMind: { valence: 0.5 }, value: true },
  { deleted: { uuid: U(99), type: "HKQuantityTypeIdentifierHeartRate" } },
  {
    route: {
      workoutUUID: W1,
      points: [
        { t: 1760000000000, lat: 35.6, lon: 139.7, alt: 10, hAcc: 5.5 },
        { t: 1760000001000, lat: 35.61, lon: 139.71 },
      ],
    },
  },
  {
    series: {
      workoutUUID: W1,
      type: "heartRate",
      unit: "count/min",
      points: [
        { t: 1760000000000, value: 100 },
        { t: 1760000002000, value: 101.5 },
      ],
    },
  },
  String.raw`{"aggregate": {"type": "steps", "func": "sum", "intervalValue": 1, "intervalUnit": "day", "deviceFilter": "all", "bucketStart": 1760000000000, "bucketEnd": 1760086400000, "value": 1234.0, "unit": "count"}}`,
  { aggregate: { type: "hr", func: "average", intervalValue: 2, intervalUnit: "hour", deviceFilter: "watch", bucketStart: 1760000000000, bucketEnd: 1760007200000, value: null } },
  { activitySummary: { date: 1760000000000, moveKcal: 300.5, moveMode: true, standHours: 10 } },
  { activitySummary: { date: 1760000000000, localDate: "2026-10-23", moveKcal: 1, moveMode: 0 } },
  { profile: { name: "Y", email: "y@example.invalid", dateOfBirth: 946684800000, biologicalSex: "male" } },
);

const S = (n: number, extra: Record<string, unknown> = {}): Record<string, unknown> => ({ uuid: U(n), type: "t", kind: "quantity", start: 10, ...extra });
const bad = (i: number, extra: Record<string, unknown>, ...lines: (string | object)[]): string => nd(hdr(100 + i, extra), ...lines);

const ZERO = { accepted: 0, deleted: 0, duplicates: 0, routePoints: 0, seriesPoints: 0, aggregateSamples: 0, activitySummaries: 0 };
const ZERO_TEXT =
  '{"accepted": 0, "deleted": 0, "duplicates": 0, "routePoints": 0, "seriesPoints": 0, "aggregateSamples": 0, "activitySummaries": 0}';

let dir = "";
let srv: Server;
let base = "";

async function req(
  method: string,
  path: string,
  opts: { body?: string | Uint8Array; headers?: Record<string, string>; auth?: string | null } = {},
): Promise<{ status: number; type: string | null; text: string }> {
  const headers: Record<string, string> = { ...opts.headers };
  const auth = opts.auth === undefined ? `Bearer ${TOKEN}` : opts.auth;
  if (auth !== null) headers.Authorization = auth;
  const res = await fetch(base + path, { method, headers, body: opts.body });
  return { status: res.status, type: res.headers.get("content-type"), text: await res.text() };
}

const post = (body: string | Uint8Array, headers: Record<string, string> = {}): ReturnType<typeof req> =>
  req("POST", "/v1/batches", { body, headers });

function rows(sql: string): unknown[][] {
  const db = new Database(join(dir, "puls.sqlite"), { readonly: true });
  try {
    return db.query(sql).values() as unknown[][];
  } finally {
    db.close();
  }
}

beforeAll(async () => {
  dir = mkdtempSync(join(tmpdir(), "puls-receiver-test-"));
  srv = await startServer(dir);
  base = `http://127.0.0.1:${srv.port}`;
});

afterAll(async () => {
  srv?.proc.kill();
  await srv?.proc.exited;
  rmSync(dir, { recursive: true, force: true });
});

describe("startup", () => {
  test("refuses to start without PULS_TOKEN", () => {
    const d = mkdtempSync(join(tmpdir(), "puls-receiver-test-"));
    try {
      const env = receiverEnv(d);
      delete env.PULS_TOKEN;
      const p = Bun.spawnSync([process.execPath, "--no-env-file", SCRIPT], { cwd: d, env, stdout: "pipe", stderr: "pipe" });
      expect(p.exitCode).toBe(1);
      expect(p.stderr.toString()).toBe("PULS_TOKEN must be set\n");
      expect(p.stdout.toString()).toBe("");
      expect(existsSync(join(d, "puls.sqlite"))).toBe(false);
    } finally {
      rmSync(d, { recursive: true, force: true });
    }
  });

  test("rejects a non-numeric PULS_PORT", () => {
    const d = mkdtempSync(join(tmpdir(), "puls-receiver-test-"));
    try {
      const p = Bun.spawnSync([process.execPath, "--no-env-file", SCRIPT], {
        cwd: d,
        env: receiverEnv(d, { PULS_PORT: "80x" }),
        stdout: "pipe",
        stderr: "pipe",
      });
      expect(p.exitCode).toBe(1);
      expect(p.stderr.toString()).toBe("invalid PULS_PORT: 80x\n");
    } finally {
      rmSync(d, { recursive: true, force: true });
    }
  });
});

describe("GET routes and auth", () => {
  test("/healthz needs no token", async () => {
    expect(await req("GET", "/healthz", { auth: null })).toEqual({ status: 200, type: "application/json", text: '{"ok": true}' });
  });

  test("the query string is part of the path", async () => {
    expect(await req("GET", "/healthz?x=1")).toEqual({ status: 404, type: "application/json", text: '{"error": "not found"}' });
  });

  for (const auth of [null, "Bearer wrong", "Basic xx", `bearer ${TOKEN}`, `Bearer ${TOKEN}x`]) {
    test(`/v1/capabilities with Authorization ${JSON.stringify(auth)} is 401`, async () => {
      expect(await req("GET", "/v1/capabilities", { auth })).toEqual({
        status: 401,
        type: "application/json",
        text: '{"error": "unauthorized"}',
      });
    });
  }

  test("/v1/capabilities", async () => {
    const r = await req("GET", "/v1/capabilities");
    expect(r.status).toBe(200);
    expect(r.text).toBe(
      '{"protocolVersions": [1], "features": ["batches", "profile"], "server": "puls-sqlite-receiver", "version": "1"}',
    );
  });

  test("/v1/stats on an empty DB", async () => {
    const r = await req("GET", "/v1/stats");
    expect(r.status).toBe(200);
    expect(r.text).toBe(
      '{"rows": {"users": 0, "batches": 0, "samples": 0, "deletions": 0, "route_points": 0, "series_points": 0, "aggregates": 0, "activity_summaries": 0}, "sampleTypes": 0, "sampleSpan": {"first": null, "last": null}, "lastBatch": null}',
    );
  });

  test("unknown GET path is 404 after auth", async () => {
    expect((await req("GET", "/nope")).text).toBe('{"error": "not found"}');
    expect((await req("GET", "/nope", { auth: null })).status).toBe(401);
  });

  test("the access log has BaseHTTPRequestHandler's shape", async () => {
    await req("GET", "/healthz");
    await Bun.sleep(50);
    expect(srv.stderr()).toMatch(/^127\.0\.0\.1 - - \[\d{2}\/[A-Z][a-z]{2}\/\d{4} \d{2}:\d{2}:\d{2}\] "GET \/healthz HTTP\/1\.1" 200 -$/m);
  });
});

describe("POST /v1/batches rejections", () => {
  const cases: [string, string | Uint8Array, Record<string, string>, number, string][] = [
    ["X-Puls-Protocol 2", FULL, { "X-Puls-Protocol": "2" }, 400, '{"error": "unsupported protocol version", "supportedVersions": [1]}'],
    ["X-Puls-Protocol abc", FULL, { "X-Puls-Protocol": "abc" }, 400, '{"error": "unsupported protocol version", "supportedVersions": [1]}'],
    ["bad X-User-ID", FULL, { "X-User-ID": "not-a-uuid" }, 400, '{"error": "X-User-ID is not a UUID"}'],
    ["unsupported encoding", FULL, { "Content-Encoding": "br" }, 400, '{"error": "unsupported Content-Encoding: br"}'],
    ["not gzip", "not gzip", { "Content-Encoding": "gzip" }, 400, '{"error": "invalid gzip body: Error -3 while decompressing data: incorrect header check"}'],
    ["gzip cut in the stream", gzipSync(FULL).subarray(0, 30), { "Content-Encoding": "gzip" }, 400, '{"error": "invalid gzip body: truncated gzip stream"}'],
    ["gzip cut in the trailer", gzipSync(FULL).subarray(0, -3), { "Content-Encoding": "gzip" }, 400, '{"error": "invalid gzip body: truncated gzip stream"}'],
    [
      "gzip with a bad CRC",
      (() => {
        const z = Buffer.from(gzipSync(FULL));
        z.writeUInt32LE((z.readUInt32LE(z.length - 8) ^ 1) >>> 0, z.length - 8);
        return z;
      })(),
      { "Content-Encoding": "gzip" },
      400,
      '{"error": "invalid gzip body: Error -3 while decompressing data: incorrect data check"}',
    ],
    ["empty gzip body", "", { "Content-Encoding": "gzip" }, 400, '{"error": "invalid gzip body: truncated gzip stream"}'],
    ["empty body", "", {}, 400, '{"error": "batch header 1/1: unexpected end of body"}'],
    ["blank lines only", "\n  \n", {}, 400, '{"error": "batch header 1/1: unexpected end of body"}'],
    ["null header", "null\n", {}, 400, '{"error": "batch header 1: missing or null object"}'],
    ["list header", "[1]\n", {}, 400, '{"error": "batch header 1: missing or null object"}'],
    ["invalid UTF-8", new Uint8Array([0xff, 0xfe, 0x0a]), {}, 400, `{"error": "'utf-8' codec can't decode the body: invalid UTF-8"}`],
    ["schemaVersion 2", bad(1, { schemaVersion: 2 }), {}, 400, '{"error": "unsupported protocol version", "supportedVersions": [1]}'],
    ["empty type", bad(2, { type: "" }), {}, 400, '{"error": "invalid batch header: batchID must be a UUID and type non-empty"}'],
    ["bad batchID", nd({ batchID: "x", type: "d" }), {}, 400, '{"error": "invalid batch header: batchID must be a UUID and type non-empty"}'],
    ["boolean count", bad(3, { sampleCount: true }), {}, 400, '{"error": "invalid batch header: counts must be integers 0..100000"}'],
    ["float count", `{"batchID":"${U(103)}","type":"d","sampleCount":1.0}\n`, {}, 400, '{"error": "invalid batch header: counts must be integers 0..100000"}'],
    ["negative count", bad(4, { sampleCount: -1 }), {}, 400, '{"error": "invalid batch header: counts must be integers 0..100000"}'],
    ["count over 100000", bad(5, { sampleCount: 100001 }), {}, 400, '{"error": "invalid batch header: counts must be integers 0..100000"}'],
    ["two profiles", bad(6, { profileCount: 2 }), {}, 400, '{"error": "invalid batch header: too many declared lines"}'],
    ["over 200000 lines", bad(7, { sampleCount: 100000, deletionCount: 100000, routeCount: 1 }), {}, 400, '{"error": "invalid batch header: too many declared lines"}'],
    ["unknown kind", bad(8, { sampleCount: 1 }, S(1, { kind: "nope" })), {}, 400, '{"error": "sample 1: bad uuid, type, kind, or start"}'],
    ["category without detail", bad(9, { sampleCount: 1 }, S(1, { kind: "category" })), {}, 400, '{"error": "sample 1: category sample missing category"}'],
    ["boolean start", bad(22, { sampleCount: 1 }, S(20, { start: true })), {}, 400, '{"error": "sample 1: bad uuid, type, kind, or start"}'],
    ["zero start", bad(25, { sampleCount: 1 }, S(20, { start: 0 })), {}, 400, '{"error": "sample 1: bad uuid, type, kind, or start"}'],
    ["fewer lines than declared", bad(11, { sampleCount: 2 }), {}, 400, '{"error": "sample 1/2: unexpected end of body"}'],
    ["trailing line", bad(12, {}, S(1), S(2)), {}, 400, '{"error": "unexpected trailing line after the declared counts"}'],
    ["null deleted wrapper", bad(13, { deletionCount: 1 }, { deleted: null }), {}, 400, '{"error": "deletion 1: missing or null deleted"}'],
    ["route point at t=0", bad(14, { routeCount: 1 }, { route: { workoutUUID: W1, points: [{ t: 0, lat: 1, lon: 2 }] } }), {}, 400, '{"error": "route 1: bad point"}'],
    [
      "route over 4000 points",
      bad(15, { routeCount: 1 }, { route: { workoutUUID: W1, points: Array.from({ length: 4001 }, () => ({ t: 1, lat: 1 })) } }),
      {},
      400,
      '{"error": "route 1: points must be a list of at most 4000"}',
    ],
    [
      "float intervalValue",
      bad(16, { aggregateCount: 1 }, String.raw`{"aggregate":{"type":"a","func":"sum","intervalValue":1.0,"intervalUnit":"day","deviceFilter":"all","bucketStart":1,"bucketEnd":2}}`),
      {},
      400,
      '{"error": "aggregate 1: bad type, func, interval, or deviceFilter"}',
    ],
    [
      "empty bucket",
      bad(17, { aggregateCount: 1 }, { aggregate: { type: "a", func: "sum", intervalValue: 1, intervalUnit: "day", deviceFilter: "all", bucketStart: 2, bucketEnd: 2 } }),
      {},
      400,
      '{"error": "aggregate 1: bucketEnd must be after bucketStart"}',
    ],
    ["moveMode 2", bad(18, { activitySummaryCount: 1 }, { activitySummary: { date: 5, moveMode: 2 } }), {}, 400, '{"error": "activity summary 1: bad date or moveMode"}'],
    ["short localDate", bad(19, { activitySummaryCount: 1 }, { activitySummary: { date: 5, localDate: "2026-1-01" } }), {}, 400, '{"error": "activity summary 1: invalid localDate"}'],
    ["header disagrees with X-Puls-Protocol", bad(21, { schemaVersion: 2 }), { "X-Puls-Protocol": "1" }, 400, '{"error": "unsupported protocol version", "supportedVersions": [1]}'],
  ];
  for (const [name, body, headers, status, text] of cases) {
    test(name, async () => {
      expect(await post(body, headers)).toEqual({ status, type: "application/json", text });
    });
  }

  test("invalid JSON in a sample line", async () => {
    const r = await post(bad(10, { sampleCount: 1 }, "{not json"));
    expect(r.status).toBe(400);
    expect(JSON.parse(r.text).error).toStartWith("sample 1: invalid JSON: ");
  });

  test("POST to another path is 404", async () => {
    expect(await req("POST", "/v1/other", { body: FULL })).toEqual({ status: 404, type: "application/json", text: '{"error": "not found"}' });
  });

  test("unauthorized POST is 401 before the path is checked", async () => {
    const r = await req("POST", "/v1/other", { body: FULL, auth: "Bearer nope" });
    expect(r).toEqual({ status: 401, type: "application/json", text: '{"error": "unauthorized"}' });
  });

  test("a value SQLite cannot bind is a 500 and rolls back the whole batch", async () => {
    const r = await post(bad(20, { sampleCount: 1 }, S(1, { value: { x: 1 } })));
    expect(r).toEqual({ status: 500, type: "application/json", text: '{"error": "insert failed"}' });
    expect(rows("SELECT COUNT(*) FROM batches")).toEqual([[0]]);
    expect(rows("SELECT COUNT(*) FROM samples")).toEqual([[0]]);
    await Bun.sleep(50);
    expect(srv.stderr()).toContain("insert failed: Error binding parameter 7: type 'dict' is not supported");
  });

  test("nothing was written by the rejected batches", async () => {
    expect(rows("SELECT (SELECT COUNT(*) FROM batches) + (SELECT COUNT(*) FROM samples) + (SELECT COUNT(*) FROM users)")).toEqual([[0]]);
  });
});

describe("accepted batches and stored rows", () => {
  test("headers-only batches are accepted (legacy schemaVersion spellings)", async () => {
    expect(await post(bad(23, { sampleCount: "", schemaVersion: true }))).toEqual({ status: 200, type: "application/json", text: ZERO_TEXT });
    expect(await post(`{"batchID":"${U(124)}","type":"delta","schemaVersion":1.0}\n`, { "X-Puls-Protocol": "01" })).toEqual({
      status: 200,
      type: "application/json",
      text: ZERO_TEXT,
    });
    expect(rows("SELECT batch_id, schema_version, typeof(schema_version) FROM batches ORDER BY batch_id")).toEqual([
      [U(123), 1, "integer"],
      [U(124), 1, "integer"],
    ]);
  });

  test("full gzip batch; trailing bytes after the gzip member are ignored", async () => {
    const body = Buffer.concat([gzipSync(FULL), Buffer.from("trailing junk")]);
    const r = await post(body, { "Content-Encoding": "gzip", "X-Puls-Protocol": "1" });
    expect(r.status).toBe(200);
    expect(JSON.parse(r.text)).toEqual({ ...ZERO, accepted: 4, routePoints: 2, seriesPoints: 2, aggregateSamples: 2, activitySummaries: 2 });
  });

  test("sample rows keep Python's typing and json.dumps line", () => {
    expect(
      rows(
        "SELECT uuid, user_id, type, kind, start_ms, typeof(start_ms), end_ms, value, typeof(value), unit, category, typeof(category), source_name, device, line FROM samples ORDER BY uuid",
      ),
    ).toEqual([
      [U(1), DEFAULT_USER, "HKQuantityTypeIdentifierHeartRate", "quantity", 1760000000000, "real", 1760000001000, 72, "real", "count/min", null, "null", NAME, "Watch7,1", SAMPLE1_STORED],
      [U(2), DEFAULT_USER, "HKCategoryTypeIdentifierSleepAnalysis", "category", 1760000000000, "real", 1760000000000, null, "null", null, 3, "integer", 'Tab\there\x7f"q"\\', null, SAMPLE2_STORED],
      [U(4), DEFAULT_USER, "Mood", "stateOfMind", -1500.5, "real", -1500.5, 1, "real", null, null, "null", null, null, `{"uuid":"${U(4)}","type":"Mood","kind":"stateOfMind","start":-1500.5,"stateOfMind":{"valence":0.5},"value":true}`],
      [W1, DEFAULT_USER, "HKWorkoutTypeIdentifier", "workout", 1760000000000, "real", 1760003600000, null, "null", null, null, "null", null, null, `{"uuid":"${W1}","type":"HKWorkoutTypeIdentifier","kind":"workout","start":1760000000000,"end":1760003600000,"workout":{"activity":37}}`],
    ]);
  });

  test("batch, user, deletion, route, series, aggregate and activity rows", () => {
    expect(rows("SELECT batch_id, user_id, device_id, type, reason, schema_version, client_version, exported_at_ms FROM batches WHERE batch_id = '" + U(1) + "'")).toEqual([
      [U(1), DEFAULT_USER, "dev-1", "delta", "bg", 1, "1.2", 1760000000123.5],
    ]);
    expect(rows("SELECT batch_id, received_at FROM batches WHERE batch_id = '" + U(1) + "'")[0][1]).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+00:00$/);
    expect(rows("SELECT id, name, email, date_of_birth_ms, biological_sex, updated_at IS NOT NULL FROM users")).toEqual([
      [DEFAULT_USER, "Y", "y@example.invalid", 946684800000, "male", 1],
    ]);
    // the deletion of an unknown UUID is recorded but deletes nothing
    expect(rows("SELECT uuid, user_id, type FROM deletions")).toEqual([[U(99), DEFAULT_USER, "HKQuantityTypeIdentifierHeartRate"]]);
    expect(rows("SELECT workout_uuid, t_ms, lat, lon, alt, h_acc, v_acc, speed, course FROM route_points ORDER BY t_ms")).toEqual([
      [W1, 1760000000000, 35.6, 139.7, 10, 5.5, null, null, null],
      [W1, 1760000001000, 35.61, 139.71, null, null, null, null, null],
    ]);
    expect(rows("SELECT workout_uuid, type, t_ms, value, unit FROM series_points ORDER BY t_ms")).toEqual([
      [W1, "heartRate", 1760000000000, 100, "count/min"],
      [W1, "heartRate", 1760000002000, 101.5, "count/min"],
    ]);
    expect(
      rows("SELECT type, func, interval_value, typeof(interval_value), interval_unit, device_filter, bucket_start_ms, bucket_end_ms, value, unit FROM aggregates ORDER BY type"),
    ).toEqual([
      ["hr", "average", 2, "integer", "hour", "watch", 1760000000000, 1760007200000, null, null],
      ["steps", "sum", 1, "integer", "day", "all", 1760000000000, 1760086400000, 1234, "count"],
    ]);
    // without localDate the key is the UTC day of `date`
    expect(rows("SELECT date, move_kcal, stand_hours, move_mode, typeof(move_mode) FROM activity_summaries ORDER BY date")).toEqual([
      ["2025-10-09", 300.5, 10, 1, "integer"],
      ["2026-10-23", 1, null, 0, "integer"],
    ]);
  });

  test("a replayed batchID is a no-op counted as duplicates", async () => {
    const r = await post(gzipSync(FULL), { "Content-Encoding": "gzip" });
    expect(JSON.parse(r.text)).toEqual({ ...ZERO, duplicates: 4 });
    // a different user replaying the same batchID is still a duplicate, but the user row appears
    const r2 = await post(FULL, { "X-User-ID": U(777) });
    expect(JSON.parse(r2.text)).toEqual({ ...ZERO, duplicates: 4 });
    expect(rows("SELECT id, name FROM users ORDER BY id")).toEqual([
      [U(777), null],
      [DEFAULT_USER, "Y"],
    ]);
    expect(rows("SELECT COUNT(*) FROM samples")).toEqual([[4]]);
  });

  test("a known sample UUID in a new batch is a duplicate, not an overwrite", async () => {
    const r = await post(nd(hdr(3, { sampleCount: 2 }), S(1, { type: "changed" }), S(6)));
    expect(JSON.parse(r.text)).toEqual({ ...ZERO, accepted: 1, duplicates: 1 });
    expect(rows(`SELECT type FROM samples WHERE uuid = '${U(1)}'`)).toEqual([["HKQuantityTypeIdentifierHeartRate"]]);
  });

  test("deleting a workout removes its sample and points; deletions run after inserts", async () => {
    const body = nd(hdr(2, { sampleCount: 1, deletionCount: 1, schemaVersion: null }), { uuid: U(5), type: "x", kind: "quantity", start: 5 }, {
      deleted: { uuid: W1, type: "HKWorkoutTypeIdentifier" },
    });
    const r = await post(body, { "Content-Encoding": "identity" });
    expect(JSON.parse(r.text)).toEqual({ ...ZERO, accepted: 1, deleted: 1 });
    expect(rows(`SELECT COUNT(*) FROM samples WHERE uuid = '${W1}'`)).toEqual([[0]]);
    expect(rows("SELECT COUNT(*) FROM route_points")).toEqual([[0]]);
    expect(rows("SELECT COUNT(*) FROM series_points")).toEqual([[0]]);
    expect(rows("SELECT uuid FROM deletions ORDER BY uuid")).toEqual([[U(99)], [W1]]);
    expect(rows(`SELECT schema_version FROM batches WHERE batch_id = '${U(2)}'`)).toEqual([[1]]);
  });

  test("aggregates and activity summaries upsert; a profile is a full snapshot", async () => {
    const body = nd(
      hdr(4, { aggregateCount: 1, activitySummaryCount: 1, profileCount: 1 }),
      { aggregate: { type: "steps", func: "sum", intervalValue: 1, intervalUnit: "day", deviceFilter: "all", bucketStart: 1760000000000, bucketEnd: 1760086400001, value: null } },
      { activitySummary: { date: 1760000000000, localDate: "2026-10-23", exerciseMin: 30 } },
      { profile: { name: "Z" } },
    );
    expect(JSON.parse((await post(body)).text)).toEqual({ ...ZERO, aggregateSamples: 1, activitySummaries: 1 });
    expect(rows("SELECT bucket_end_ms, value, unit FROM aggregates WHERE type = 'steps'")).toEqual([[1760086400001, null, null]]);
    expect(rows("SELECT move_kcal, exercise_min, move_mode FROM activity_summaries WHERE date = '2026-10-23'")).toEqual([[null, 30, null]]);
    expect(rows(`SELECT name, email, date_of_birth_ms, biological_sex FROM users WHERE id = '${DEFAULT_USER}'`)).toEqual([["Z", null, null, null]]);
  });

  test("/v1/stats after the batches", async () => {
    const r = await req("GET", "/v1/stats");
    expect(r.status).toBe(200);
    const body = JSON.parse(r.text);
    expect(body.rows).toEqual({
      users: 2,
      batches: 6,
      samples: 5,
      deletions: 2,
      route_points: 0,
      series_points: 0,
      aggregates: 2,
      activity_summaries: 2,
    });
    expect(body.sampleTypes).toBe(5);
    expect(body.sampleSpan).toEqual({ first: "1969-12-31T23:59:58+00:00", last: "2025-10-09T08:53:20+00:00" });
    expect(body.lastBatch).toMatchObject({ type: "delta", reason: "bg" });
    expect(body.lastBatch.receivedAt).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+00:00$/);
  });
});

describe("size caps and unsupported methods", () => {
  test("PUT and DELETE get the BaseHTTPRequestHandler 501 page", async () => {
    for (const method of ["PUT", "DELETE"]) {
      const r = await req(method, "/v1/batches", { body: method === "PUT" ? "x" : undefined });
      expect(r.status).toBe(501);
      expect(r.type).toBe("text/html;charset=utf-8");
      expect(r.text).toContain(`<p>Message: Unsupported method ('${method}').</p>`);
      expect(r.text).toContain("<p>Error code explanation: 501 - Server does not support this operation.</p>");
    }
    await Bun.sleep(50);
    expect(srv.stderr()).toMatch(/\] code 501, message Unsupported method \('PUT'\)\n/);
  });

  test("HEAD is 501 without a body", async () => {
    const res = await fetch(`${base}/healthz`, { method: "HEAD" });
    expect(res.status).toBe(501);
    expect(await res.text()).toBe("");
  });

  test("an oversized Content-Length is 413 before the body is read", async () => {
    const raw = await new Promise<string>((resolve, reject) => {
      const sock = connect(srv.port, "127.0.0.1");
      let got = "";
      sock.on("data", (d) => {
        got += d.toString();
        if (got.includes('"}')) {
          sock.destroy();
          resolve(got);
        }
      });
      sock.on("error", reject);
      sock.on("close", () => resolve(got));
      sock.write(
        `POST /v1/batches HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer ${TOKEN}\r\nContent-Length: ${(256 << 20) + 1}\r\n\r\n`,
      );
    });
    expect(raw).toStartWith("HTTP/1.1 413");
    expect(raw).toEndWith('{"error": "body too large"}');
  });

  test("a gzip body inflating past 512 MiB is 413", async () => {
    const bomb = gzipSync(new Uint8Array((512 << 20) + 1), { level: 1 });
    expect(await post(bomb, { "Content-Encoding": "gzip" })).toEqual({
      status: 413,
      type: "application/json",
      text: '{"error": "decompressed body too large"}',
    });
  }, 20_000);
});
