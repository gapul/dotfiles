#!/usr/bin/env bun
// Derived from PulsHealth's examples/receivers/python-sqlite/receiver.py
// (https://github.com/PulsHealth/pulshealth, commit 4a39d39b), Apache License 2.0,
// Copyright 2026 Sean Wade. See NOTICE in this directory.
//
// Changes from upstream:
//   - the gzip body is decompressed with a cap (MAX_RAW). Upstream bounds the compressed
//     size only, so a small highly compressible body could expand without limit in memory.
//   - GET /v1/stats, which is not part of the protocol. The DB lives under a DynamicUser
//     StateDirectory (0700), so counting rows over SSH otherwise means root; this answers
//     "did anything arrive" with the token the sender already holds.
//   - ported from receiver.py (Python standard library) to TypeScript on Bun. The wire
//     contract, the SQLite schema and the stored values are the same; JSON is written the way
//     Python's json.dumps writes it (", "/": " separators, \uXXXX escapes, 72.0 stays 72.0),
//     so bodies and the samples.line column match byte for byte.
//
// Minimal Puls Sync Protocol v1 receiver: HTTP in, SQLite out, no dependencies beyond Bun.
//
// Implements the receiver side of docs/protocol/README.md:
//
//     POST /v1/batches       gzip NDJSON batch -> idempotent SQLite writes -> JSON counts
//     GET  /v1/capabilities  {"protocolVersions":[1],"features":["batches","profile"],...}
//     GET  /v1/stats         row counts, the sample time span, and the last batch (local addition)
//     GET  /healthz          {"ok":true}
//
// Environment: PULS_TOKEN (required), PULS_DB (default puls.sqlite),
// PULS_BIND (default 127.0.0.1), PULS_PORT (default 8080).
import { Database } from "bun:sqlite";
import { timingSafeEqual } from "node:crypto";
import { writeSync } from "node:fs";
import { inflateRawSync } from "node:zlib";

const PROTOCOL_VERSIONS = [1];
const DEFAULT_USER = "5ea4d000-0000-4000-8000-000000000001";
const MAX_BODY = 256 << 20; // compressed bytes, as the reference server
const MAX_RAW = 512 << 20; // decompressed bytes; the app pages batches far below this
const COUNTS = [
  "sampleCount",
  "deletionCount",
  "routeCount",
  "seriesCount",
  "aggregateCount",
  "activitySummaryCount",
  "profileCount",
] as const;
// kind -> the detail field that must be present for that kind
const KINDS = new Map<unknown, string | null>([
  ["quantity", null],
  ["category", "category"],
  ["workout", "workout"],
  ["heartbeatSeries", "heartbeats"],
  ["ecg", "ecg"],
  ["stateOfMind", "stateOfMind"],
  ["medicationDose", "medicationDose"],
]);
const AGG_ENUMS: [string, Set<unknown>][] = [
  ["func", new Set(["sum", "average", "min", "max", "mostRecent", "duration"])],
  ["intervalUnit", new Set(["minute", "hour", "day", "week", "month"])],
  ["deviceFilter", new Set(["all", "watch", "iphone"])],
];
// Python's re.match with `$` also accepts one trailing newline; kept so the same IDs pass.
const UUID_RE = /^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}\n?$/;
const ZERO_RESULT = {
  accepted: 0,
  deleted: 0,
  duplicates: 0,
  routePoints: 0,
  seriesPoints: 0,
  aggregateSamples: 0,
  activitySummaries: 0,
};
// Counted by /v1/stats. Interpolated into SQL, so this list is the only allowed source of names.
const STAT_TABLES = [
  "users",
  "batches",
  "samples",
  "deletions",
  "route_points",
  "series_points",
  "aggregates",
  "activity_summaries",
] as const;

const SCHEMA = `
CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, name TEXT, email TEXT, date_of_birth_ms REAL,
    biological_sex TEXT, updated_at TEXT);
CREATE TABLE IF NOT EXISTS batches (batch_id TEXT PRIMARY KEY, user_id TEXT NOT NULL, device_id TEXT, type TEXT,
    reason TEXT, schema_version INTEGER, client_version TEXT, exported_at_ms REAL, received_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS samples (uuid TEXT PRIMARY KEY, user_id TEXT NOT NULL, type TEXT NOT NULL,
    kind TEXT NOT NULL, start_ms REAL NOT NULL, end_ms REAL NOT NULL, value REAL, unit TEXT, category INTEGER,
    source_name TEXT, device TEXT, line TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS samples_by_type ON samples (user_id, type, start_ms);
CREATE TABLE IF NOT EXISTS deletions (uuid TEXT PRIMARY KEY, user_id TEXT NOT NULL, type TEXT NOT NULL,
    deleted_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS route_points (workout_uuid TEXT NOT NULL, t_ms REAL NOT NULL, user_id TEXT NOT NULL,
    lat REAL NOT NULL, lon REAL NOT NULL, alt REAL, h_acc REAL, v_acc REAL, speed REAL, course REAL,
    PRIMARY KEY (workout_uuid, t_ms));
CREATE TABLE IF NOT EXISTS series_points (workout_uuid TEXT NOT NULL, type TEXT NOT NULL, t_ms REAL NOT NULL,
    user_id TEXT NOT NULL, value REAL NOT NULL, unit TEXT, PRIMARY KEY (workout_uuid, type, t_ms));
CREATE TABLE IF NOT EXISTS aggregates (user_id TEXT NOT NULL, type TEXT NOT NULL, func TEXT NOT NULL,
    interval_value INTEGER NOT NULL, interval_unit TEXT NOT NULL, device_filter TEXT NOT NULL,
    bucket_start_ms REAL NOT NULL, bucket_end_ms REAL NOT NULL, value REAL, unit TEXT, updated_at TEXT NOT NULL,
    PRIMARY KEY (user_id, type, func, interval_value, interval_unit, device_filter, bucket_start_ms));
CREATE TABLE IF NOT EXISTS activity_summaries (user_id TEXT NOT NULL, date TEXT NOT NULL, move_kcal REAL,
    move_goal_kcal REAL, exercise_min REAL, exercise_goal_min REAL, stand_hours REAL, stand_goal_hours REAL,
    move_mode INTEGER, move_time_min REAL, move_time_goal_min REAL, updated_at TEXT NOT NULL,
    PRIMARY KEY (user_id, date));
`;

/** Malformed input: answered with 400, which the app never retries. */
class BadRequest extends Error {}

/** A protocol version this receiver does not speak: fixed 400 body. */
class UnsupportedVersion extends Error {}

/** A value SQLite cannot bind (a JSON object or list), like sqlite3's ProgrammingError. */
class BindError extends Error {}

// --- Python value semantics -------------------------------------------------------------------
// The validation below was written against json.loads' output, where 1 and 1.0 are different
// types and [] / {} are falsy. JSON.parse keeps neither, so the parser records which numbers
// were written as floats, keyed by the object or array that holds them.

type Obj = Record<string, unknown>;
const floats = new WeakMap<object, Set<string>>();

function parseJson(text: string): unknown {
  return JSON.parse(text, function (this: object, key: string, value: unknown, ctx?: { source?: string }) {
    if (typeof value === "number" && /[.eE]/.test(ctx?.source ?? (Number.isInteger(value) ? "" : "."))) {
      let set = floats.get(this);
      if (!set) floats.set(this, (set = new Set()));
      set.add(key);
    }
    return value;
  });
}

const isDict = (v: unknown): v is Obj => typeof v === "object" && v !== null && !Array.isArray(v);
// dict.get(): own keys only, so "constructor" or "__proto__" never reach Object.prototype
const get = (o: Obj, k: string): unknown => (Object.hasOwn(o, k) ? o[k] : undefined);
const none = (v: unknown): v is null | undefined => v === null || v === undefined;
const falsy = (v: unknown): boolean =>
  none(v) ||
  v === false ||
  v === 0 ||
  v === "" ||
  (Array.isArray(v) && v.length === 0) ||
  (isDict(v) && Object.keys(v).length === 0);
const or = (v: unknown, fallback: unknown): unknown => (falsy(v) ? fallback : v);
// isinstance(o[k], int) and not bool
const isIntAt = (o: object, k: string): boolean => {
  const v = (o as Obj)[k];
  return typeof v === "number" && Number.isInteger(v) && !floats.get(o)?.has(k);
};
// `v in (1,)` compares with ==, so True and 1.0 count as 1
const eqOne = (v: unknown): boolean => v === 1 || v === true;

// Python's float repr: shortest round trip, exponent outside 1e-4..1e16, ".0" when integral.
function floatRepr(x: number): string {
  if (Number.isNaN(x)) return "NaN";
  if (!Number.isFinite(x)) return x > 0 ? "Infinity" : "-Infinity";
  if (x === 0) return Object.is(x, -0) ? "-0.0" : "0.0";
  const sign = x < 0 ? "-" : "";
  const [mantissa, expText] = Math.abs(x).toExponential().split("e");
  const digits = mantissa.replace(".", "");
  const exp = Number(expText);
  if (exp >= -4 && exp < 16) {
    if (exp < 0) return `${sign}0.${"0".repeat(-exp - 1)}${digits}`;
    const whole = digits.slice(0, exp + 1).padEnd(exp + 1, "0");
    return `${sign}${whole}.${digits.slice(exp + 1) || "0"}`;
  }
  const m = digits.length > 1 ? `${digits[0]}.${digits.slice(1)}` : digits;
  return `${sign}${m}e${exp < 0 ? "-" : "+"}${String(Math.abs(exp)).padStart(2, "0")}`;
}

// json.dumps with ensure_ascii: everything outside printable ASCII becomes \uXXXX.
function strRepr(s: string): string {
  let out = '"';
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    const ch = s[i];
    if (ch === '"') out += '\\"';
    else if (ch === "\\") out += "\\\\";
    else if (ch === "\n") out += "\\n";
    else if (ch === "\r") out += "\\r";
    else if (ch === "\t") out += "\\t";
    else if (ch === "\b") out += "\\b";
    else if (ch === "\f") out += "\\f";
    else if (c < 0x20 || c > 0x7e) out += `\\u${c.toString(16).padStart(4, "0")}`;
    else out += ch;
  }
  return `${out}"`;
}

/** json.dumps(value) (compact=false) or json.dumps(value, separators=(",", ":")). */
function dumps(value: unknown, compact = false): string {
  const [item, kv] = compact ? [",", ":"] : [", ", ": "];
  const walk = (v: unknown, holder: object | null, key: string): string => {
    if (none(v)) return "null";
    if (v === true) return "true";
    if (v === false) return "false";
    if (typeof v === "number") {
      const isFloat = !Number.isInteger(v) || (holder !== null && floats.get(holder)?.has(key));
      return isFloat ? floatRepr(v) : BigInt(v).toString();
    }
    if (typeof v === "string") return strRepr(v);
    if (Array.isArray(v)) return `[${v.map((x, i) => walk(x, v, String(i))).join(item)}]`;
    const o = v as Obj;
    return `{${Object.keys(o)
      .map((k) => `${strRepr(k)}${kv}${walk(o[k], o, k)}`)
      .join(item)}}`;
  };
  return walk(value, null, "");
}

// sqlite3 binds None/bool/int/float/str and refuses containers.
type Bound = string | number | null;
function bind(v: unknown, i: number): Bound {
  if (none(v)) return null;
  if (typeof v === "boolean") return v ? 1 : 0;
  if (typeof v === "number" || typeof v === "string") return v;
  throw new BindError(`Error binding parameter ${i + 1}: type '${Array.isArray(v) ? "list" : "dict"}' is not supported`);
}
const binds = (...vs: unknown[]): Bound[] => vs.map((v, i) => bind(v, i));

// --- protocol ---------------------------------------------------------------------------------

const isUuid = (v: unknown): v is string => typeof v === "string" && UUID_RE.test(v);

/** A required epoch-ms timestamp: a number in year 1..9999, not 0 (0 means absent). */
const isMs = (v: unknown): v is number =>
  typeof v === "number" && v !== 0 && v >= -62135596800000 && v <= 253402300799999;

// datetime.isoformat(timespec="seconds") in UTC
const isoSeconds = (ms: number): string => `${new Date(Math.floor(ms)).toISOString().slice(0, 19)}+00:00`;
const now = (): string => isoSeconds(Date.now());

interface Batch {
  header: Obj;
  samples: Obj[];
  deletions: Obj[];
  routes: Obj[];
  series: Obj[];
  aggregates: Obj[];
  activitySummaries: Obj[];
  profile: Obj | null;
}

/** NDJSON text -> validated lines in wire order. Throws BadRequest/UnsupportedVersion. */
function parseBatch(text: string): Batch {
  const lines = text.split("\n").filter((line) => line.trim());
  let next = 0;

  function* take(n: number, what: string, key?: string): Generator<[number, Obj]> {
    for (let i = 1; i <= n; i++) {
      if (next >= lines.length) throw new BadRequest(`${what} ${i}/${n}: unexpected end of body`);
      let obj: unknown;
      try {
        obj = parseJson(lines[next++]);
      } catch (e) {
        throw new BadRequest(`${what} ${i}: invalid JSON: ${(e as Error).message}`);
      }
      if (key) obj = isDict(obj) ? get(obj, key) : undefined; // wrapped line: the wrapper key must hold a non-null object
      if (!isDict(obj)) throw new BadRequest(`${what} ${i}: missing or null ${key || "object"}`);
      yield [i, obj];
    }
  }

  function points(inner: Obj, what: string, i: number, ...required: string[]): void {
    const pts = get(inner, "points");
    if (!Array.isArray(pts) || pts.length > 4000) {
      throw new BadRequest(`${what} ${i}: points must be a list of at most 4000`);
    }
    for (const p of pts) {
      if (!isDict(p) || !isMs(get(p, "t")) || required.some((k) => none(get(p, k)))) {
        throw new BadRequest(`${what} ${i}: bad point`);
      }
    }
  }

  const [, header] = take(1, "batch header").next().value as [number, Obj];
  const version = get(header, "schemaVersion"); // absent or null = legacy client = 1
  if (!none(version) && !eqOne(version)) throw new UnsupportedVersion(`schemaVersion ${String(version)}`);
  if (!isUuid(get(header, "batchID")) || falsy(get(header, "type"))) {
    throw new BadRequest("invalid batch header: batchID must be a UUID and type non-empty");
  }
  const counts = {} as Record<(typeof COUNTS)[number], number>;
  let countsOk = true;
  for (const k of COUNTS) {
    const raw = get(header, k);
    const n = or(raw, 0);
    if (typeof n !== "number" || !(falsy(raw) || isIntAt(header, k)) || n < 0 || n > 100_000) countsOk = false;
    counts[k] = n as number;
  }
  if (!countsOk) throw new BadRequest("invalid batch header: counts must be integers 0..100000");
  if (counts.profileCount > 1 || Object.values(counts).reduce((a, b) => a + b, 0) > 200_000) {
    throw new BadRequest("invalid batch header: too many declared lines");
  }

  const b: Batch = {
    header,
    samples: [],
    deletions: [],
    routes: [],
    series: [],
    aggregates: [],
    activitySummaries: [],
    profile: null,
  };
  for (const [i, s] of take(counts.sampleCount, "sample")) {
    const kind = get(s, "kind");
    if (!isUuid(get(s, "uuid")) || falsy(get(s, "type")) || !KINDS.has(kind) || !isMs(get(s, "start"))) {
      throw new BadRequest(`sample ${i}: bad uuid, type, kind, or start`);
    }
    const detail = KINDS.get(kind);
    if (detail && none(get(s, detail))) throw new BadRequest(`sample ${i}: ${kind} sample missing ${detail}`);
    b.samples.push(s);
  }
  for (const [i, d] of take(counts.deletionCount, "deletion", "deleted")) {
    if (!isUuid(get(d, "uuid")) || falsy(get(d, "type"))) throw new BadRequest(`deletion ${i}: bad uuid or type`);
    b.deletions.push(d);
  }
  for (const [i, r] of take(counts.routeCount, "route", "route")) {
    if (!isUuid(get(r, "workoutUUID"))) throw new BadRequest(`route ${i}: workoutUUID is not a UUID`);
    points(r, "route", i, "lat", "lon");
    b.routes.push(r);
  }
  for (const [i, s] of take(counts.seriesCount, "series", "series")) {
    if (!isUuid(get(s, "workoutUUID")) || falsy(get(s, "type"))) {
      throw new BadRequest(`series ${i}: bad workoutUUID or type`);
    }
    points(s, "series", i, "value");
    b.series.push(s);
  }
  for (const [i, a] of take(counts.aggregateCount, "aggregate", "aggregate")) {
    const iv = get(a, "intervalValue");
    if (
      falsy(get(a, "type")) ||
      AGG_ENUMS.some(([k, v]) => !v.has(get(a, k))) ||
      !isIntAt(a, "intervalValue") ||
      (iv as number) < 1
    ) {
      throw new BadRequest(`aggregate ${i}: bad type, func, interval, or deviceFilter`);
    }
    const start = get(a, "bucketStart");
    const end = get(a, "bucketEnd");
    if (!isMs(start) || !isMs(end) || end <= start) {
      throw new BadRequest(`aggregate ${i}: bucketEnd must be after bucketStart`);
    }
    b.aggregates.push(a);
  }
  for (const [i, a] of take(counts.activitySummaryCount, "activity summary", "activitySummary")) {
    const mode = get(a, "moveMode");
    if (!isMs(get(a, "date")) || !(none(mode) || mode === 0 || eqOne(mode) || mode === false)) {
      throw new BadRequest(`activity summary ${i}: bad date or moveMode`);
    }
    const localDate = get(a, "localDate");
    // re.fullmatch(r"\d{4}-\d{2}-\d{2}", str(...)); Python's \d is any Unicode digit
    if (!none(localDate) && !(typeof localDate === "string" && /^\p{Nd}{4}-\p{Nd}{2}-\p{Nd}{2}$/u.test(localDate))) {
      throw new BadRequest(`activity summary ${i}: invalid localDate`);
    }
    b.activitySummaries.push(a);
  }
  for (const [, p] of take(counts.profileCount, "profile", "profile")) b.profile = p;
  if (next < lines.length) throw new BadRequest("unexpected trailing line after the declared counts");
  return b;
}

/** Upsert key for an activity summary: localDate, else the UTC day of the legacy date. */
const localDay = (a: Obj): unknown =>
  or(get(a, "localDate"), new Date(Math.floor(get(a, "date") as number)).toISOString().slice(0, 10));

type Result = typeof ZERO_RESULT;

/** One transaction per batch. A replayed batchID is a no-op; deletions run last. */
function applyBatch(db: Database, b: Batch, userId: string): Result {
  const h = b.header;
  const res: Result = { ...ZERO_RESULT };
  const ts = now();
  const run = (sql: string, ...vs: unknown[]): number => db.query(sql).run(...binds(...vs)).changes;
  db.transaction(() => {
    run("INSERT OR IGNORE INTO users (id) VALUES (?)", userId);
    const fresh = run(
      "INSERT OR IGNORE INTO batches VALUES (?,?,?,?,?,?,?,?,?)",
      h.batchID,
      userId,
      get(h, "deviceID"),
      h.type,
      get(h, "reason"),
      or(get(h, "schemaVersion"), 1),
      get(h, "clientVersion"),
      get(h, "exportedAt"),
      ts,
    );
    if (!fresh) {
      res.duplicates = b.samples.length; // retried upload: already applied
      return;
    }
    for (const s of b.samples) {
      // the UUID is the identity; a known UUID is never overwritten
      res.accepted += run(
        "INSERT OR IGNORE INTO samples VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
        s.uuid,
        userId,
        s.type,
        s.kind,
        s.start,
        or(get(s, "end"), s.start),
        get(s, "value"),
        get(s, "unit"),
        get(s, "category"),
        get(s, "sourceName"),
        get(s, "device"),
        dumps(s, true),
      );
    }
    res.duplicates = b.samples.length - res.accepted;
    for (const r of b.routes) {
      for (const p of r.points as Obj[]) {
        res.routePoints += run(
          "INSERT OR IGNORE INTO route_points VALUES (?,?,?,?,?,?,?,?,?,?)",
          r.workoutUUID,
          p.t,
          userId,
          p.lat,
          p.lon,
          get(p, "alt"),
          get(p, "hAcc"),
          get(p, "vAcc"),
          get(p, "speed"),
          get(p, "course"),
        );
      }
    }
    for (const s of b.series) {
      for (const p of s.points as Obj[]) {
        res.seriesPoints += run(
          "INSERT OR IGNORE INTO series_points VALUES (?,?,?,?,?,?)",
          s.workoutUUID,
          s.type,
          p.t,
          userId,
          p.value,
          get(s, "unit"),
        );
      }
    }
    if (b.profile !== null) {
      // a complete snapshot: null or absent fields clear stored values
      const p = b.profile;
      run(
        "INSERT INTO users VALUES (?,?,?,?,?,?) ON CONFLICT (id) DO UPDATE SET name=excluded.name," +
          " email=excluded.email, date_of_birth_ms=excluded.date_of_birth_ms," +
          " biological_sex=excluded.biological_sex, updated_at=excluded.updated_at",
        userId,
        get(p, "name"),
        get(p, "email"),
        get(p, "dateOfBirth"),
        get(p, "biologicalSex"),
        ts,
      );
    }
    for (const a of b.aggregates) {
      // upsert on the bucket identity; an explicit null clears the value
      run(
        "INSERT INTO aggregates VALUES (?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT DO UPDATE SET" +
          " bucket_end_ms=excluded.bucket_end_ms, value=excluded.value, unit=excluded.unit," +
          " updated_at=excluded.updated_at",
        userId,
        a.type,
        a.func,
        a.intervalValue,
        a.intervalUnit,
        a.deviceFilter,
        a.bucketStart,
        a.bucketEnd,
        get(a, "value"),
        get(a, "unit"),
        ts,
      );
      res.aggregateSamples += 1;
    }
    for (const a of b.activitySummaries) {
      // upsert on the local day; every column is overwritten, nulls included
      run(
        "INSERT INTO activity_summaries VALUES (?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT DO UPDATE SET" +
          " move_kcal=excluded.move_kcal, move_goal_kcal=excluded.move_goal_kcal," +
          " exercise_min=excluded.exercise_min, exercise_goal_min=excluded.exercise_goal_min," +
          " stand_hours=excluded.stand_hours, stand_goal_hours=excluded.stand_goal_hours," +
          " move_mode=excluded.move_mode, move_time_min=excluded.move_time_min," +
          " move_time_goal_min=excluded.move_time_goal_min, updated_at=excluded.updated_at",
        userId,
        localDay(a),
        get(a, "moveKcal"),
        get(a, "moveGoalKcal"),
        get(a, "exerciseMin"),
        get(a, "exerciseGoalMin"),
        get(a, "standHours"),
        get(a, "standGoalHours"),
        get(a, "moveMode"),
        get(a, "moveTimeMin"),
        get(a, "moveTimeGoalMin"),
        ts,
      );
      res.activitySummaries += 1;
    }
    for (const d of b.deletions) {
      // an unknown UUID is a no-op; a deleted workout takes its points along
      res.deleted += run("DELETE FROM samples WHERE uuid=? AND user_id=?", d.uuid, userId);
      run("DELETE FROM route_points WHERE workout_uuid=? AND user_id=?", d.uuid, userId);
      run("DELETE FROM series_points WHERE workout_uuid=? AND user_id=?", d.uuid, userId);
      run("INSERT OR IGNORE INTO deletions VALUES (?,?,?,?)", d.uuid, userId, d.type, ts);
    }
  })();
  return res;
}

/** Epoch ms -> UTC ISO, or null for an empty table. */
const isoMs = (ms: number | null): string | null => (ms === null ? null : isoSeconds(ms));

/** What /v1/stats answers: how much is stored, how far it reaches, and when it last grew. */
function stats(db: Database): Obj {
  const one = <T>(sql: string): T => db.query(sql).values()[0] as T;
  const rows: Record<string, number> = {};
  for (const t of STAT_TABLES) rows[t] = one<[number]>(`SELECT COUNT(*) FROM ${t}`)[0];
  const [first, last] = one<[number | null, number | null]>("SELECT MIN(start_ms), MAX(start_ms) FROM samples");
  const batch = db.query("SELECT received_at, type, reason FROM batches ORDER BY received_at DESC LIMIT 1").values()[0];
  return {
    rows,
    sampleTypes: one<[number]>("SELECT COUNT(DISTINCT type) FROM samples")[0],
    sampleSpan: { first: isoMs(first), last: isoMs(last) },
    lastBatch: batch === undefined ? null : { receivedAt: batch[0], type: batch[1], reason: batch[2] },
  };
}

// --- gzip -------------------------------------------------------------------------------------
// Python's zlib.decompressobj(wbits=31) reads exactly one gzip member and leaves any bytes after
// it alone; node's gunzip insists on more members instead. So the header and trailer are handled
// here and only the deflate stream goes to zlib. Errors read like Python's zlib.error.

class GzipError extends Error {}
class TooLarge extends Error {}

function gunzip(raw: Uint8Array): Uint8Array {
  const truncated = (): never => {
    throw new GzipError("truncated gzip stream");
  };
  const zerr = (msg: string): never => {
    throw new GzipError(`Error -3 while decompressing data: ${msg}`);
  };
  const buf = Buffer.from(raw.buffer, raw.byteOffset, raw.byteLength);
  if (buf.length < 10) {
    if ((buf.length >= 1 && buf[0] !== 0x1f) || (buf.length >= 2 && buf[1] !== 0x8b)) zerr("incorrect header check");
    if (buf.length >= 3 && buf[2] !== 8) zerr("unknown compression method");
    truncated();
  }
  if (buf[0] !== 0x1f || buf[1] !== 0x8b) zerr("incorrect header check");
  if (buf[2] !== 8) zerr("unknown compression method");
  const flags = buf[3];
  if (flags & 0xe0) zerr("unknown header flags set");
  let pos = 10;
  if (flags & 4) {
    if (pos + 2 > buf.length) truncated();
    pos += 2 + buf.readUInt16LE(pos);
  }
  for (const bit of [8, 16]) {
    if (flags & bit) {
      const end = buf.indexOf(0, pos);
      if (end < 0) truncated();
      pos = end + 1;
    }
  }
  if (flags & 2) {
    if (pos + 2 > buf.length) truncated();
    if ((Bun.hash.crc32(buf.subarray(0, pos)) & 0xffff) !== buf.readUInt16LE(pos)) zerr("header crc mismatch");
    pos += 2;
  }
  if (pos > buf.length) truncated();
  let out: Buffer;
  let used: number;
  try {
    const r = inflateRawSync(buf.subarray(pos), { maxOutputLength: MAX_RAW, info: true }) as unknown as {
      buffer: Buffer;
      engine: { bytesWritten: number };
    };
    out = r.buffer;
    used = r.engine.bytesWritten;
  } catch (e) {
    const err = e as { code?: string; message: string };
    if (err.code === "ERR_BUFFER_TOO_LARGE") throw new TooLarge();
    if (err.code === "Z_BUF_ERROR") truncated();
    return zerr(err.message);
  }
  const trailer = pos + used;
  if (trailer + 8 > buf.length) truncated();
  if (buf.readUInt32LE(trailer) !== Bun.hash.crc32(out) >>> 0) zerr("incorrect data check");
  if (buf.readUInt32LE(trailer + 4) !== out.length >>> 0) zerr("incorrect length check");
  return out;
}

// --- HTTP -------------------------------------------------------------------------------------

const TOKEN = process.env.PULS_TOKEN;
if (!TOKEN) {
  writeSync(2, "PULS_TOKEN must be set\n");
  process.exit(1);
}
const tokenBytes = Buffer.from(TOKEN);

// BaseHTTPRequestHandler's access log on stderr: `client - - [23/Oct/2026 09:00:00] message`
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
function log(client: string, message: string): void {
  const d = new Date();
  const p = (n: number): string => String(n).padStart(2, "0");
  const stamp = `${p(d.getDate())}/${MONTHS[d.getMonth()]}/${String(d.getFullYear()).padStart(4, "0")} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
  writeSync(2, `${client} - - [${stamp}] ${message}\n`);
}

function authorized(req: Request): boolean {
  const got = req.headers.get("Authorization") ?? "";
  if (!got.startsWith("Bearer ")) return false;
  const given = Buffer.from(got.slice(7));
  return given.length === tokenBytes.length && timingSafeEqual(given, tokenBytes);
}

type Reply = { status: number; body: unknown };
const reply = (status: number, body: unknown): Reply => ({ status, body });
const unsupportedVersion = (): Reply =>
  reply(400, { error: "unsupported protocol version", supportedVersions: PROTOCOL_VERSIONS });

function doGet(req: Request, path: string, client: string, db: Database): Reply {
  if (path === "/healthz") return reply(200, { ok: true });
  if (!authorized(req)) return reply(401, { error: "unauthorized" });
  if (path === "/v1/capabilities") {
    return reply(200, {
      protocolVersions: PROTOCOL_VERSIONS,
      features: ["batches", "profile"],
      server: "puls-sqlite-receiver",
      version: "1",
    });
  }
  if (path === "/v1/stats") {
    // a single-threaded server never reads during a half-applied batch: the writes are synchronous
    try {
      return reply(200, stats(db));
    } catch (e) {
      log(client, `stats failed: ${(e as Error).message}`);
      return reply(500, { error: "stats failed" });
    }
  }
  return reply(404, { error: "not found" });
}

async function doPost(req: Request, path: string, client: string, db: Database): Promise<Reply> {
  if (!authorized(req)) return reply(401, { error: "unauthorized" });
  if (path !== "/v1/batches") return reply(404, { error: "not found" });
  const proto = (req.headers.get("X-Puls-Protocol") ?? "").trim(); // absent = legacy client
  if (proto && (!/^\d+$/.test(proto) || !PROTOCOL_VERSIONS.includes(Number(proto)))) return unsupportedVersion();
  const userId = req.headers.get("X-User-ID") || DEFAULT_USER;
  if (!isUuid(userId)) return reply(400, { error: "X-User-ID is not a UUID" });
  // Like the Python server, only a Content-Length body is read; a body without one counts as empty.
  const length = Number(req.headers.get("Content-Length") || 0);
  if (length > MAX_BODY) return reply(413, { error: "body too large" });
  let raw: Uint8Array = length > 0 ? new Uint8Array(await req.arrayBuffer()) : new Uint8Array();
  const encoding = req.headers.get("Content-Encoding") ?? "identity";
  if (encoding === "gzip") {
    try {
      raw = gunzip(raw);
    } catch (e) {
      if (e instanceof TooLarge) return reply(413, { error: "decompressed body too large" });
      return reply(400, { error: `invalid gzip body: ${(e as Error).message}` });
    }
  } else if (encoding !== "" && encoding !== "identity") {
    return reply(400, { error: `unsupported Content-Encoding: ${encoding}` });
  }
  let batch: Batch;
  try {
    let text: string;
    try {
      text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(raw);
    } catch {
      throw new BadRequest("'utf-8' codec can't decode the body: invalid UTF-8");
    }
    batch = parseBatch(text);
    const version = get(batch.header, "schemaVersion");
    if (proto && !(none(version) || (Number(proto) === 1 && eqOne(version)))) {
      throw new UnsupportedVersion("X-Puls-Protocol disagrees with schemaVersion");
    }
  } catch (e) {
    if (e instanceof UnsupportedVersion) return unsupportedVersion();
    if (e instanceof BadRequest) return reply(400, { error: e.message });
    throw e;
  }
  try {
    return reply(200, applyBatch(db, batch, userId));
  } catch (e) {
    log(client, `insert failed: ${(e as Error).message}`);
    return reply(500, { error: "insert failed" });
  }
}

// BaseHTTPRequestHandler.send_error for a method with no do_<METHOD>.
function unsupportedMethod(method: string, client: string, path: string): Response {
  const message = `Unsupported method ('${method}')`;
  log(client, `code 501, message ${message}`);
  log(client, `"${method} ${path} HTTP/1.1" 501 -`);
  const body = `<!DOCTYPE HTML>
<html lang="en">
    <head>
        <meta charset="utf-8">
        <title>Error response</title>
    </head>
    <body>
        <h1>Error response</h1>
        <p>Error code: 501</p>
        <p>Message: ${message}.</p>
        <p>Error code explanation: 501 - Server does not support this operation.</p>
    </body>
</html>
`;
  return new Response(method === "HEAD" ? null : body, {
    status: 501,
    headers: { "Content-Type": "text/html;charset=utf-8", Connection: "close", Server: "puls-sqlite-receiver/1" },
  });
}

// Validate the port first so a bad one does not leave an empty database behind.
if (!/^\s*\d+\s*$/.test(process.env.PULS_PORT ?? "8080")) {
  writeSync(2, `invalid PULS_PORT: ${process.env.PULS_PORT}\n`);
  process.exit(1);
}
const db = new Database(process.env.PULS_DB ?? "puls.sqlite");
db.exec(SCHEMA);
// Loopback by default, mirroring the reference stack's INGEST_BIND_ADDR:
// this receiver has no TLS and no throttling on failed authentications, so
// reaching it from another machine should be something you ask for, not
// something you get by running it.
const bind_ = process.env.PULS_BIND ?? "127.0.0.1";
const port = Number(process.env.PULS_PORT ?? "8080");
const server = Bun.serve({
  hostname: bind_,
  port,
  // The 413 for an oversized Content-Length is ours to send, with its JSON body.
  maxRequestBodySize: Number.MAX_SAFE_INTEGER,
  development: false,
  // Python's handler thread dies on an unexpected exception and the client sees the connection
  // close; here the request ends with a bare 500 and the error goes to the journal.
  error(e) {
    writeSync(2, `${e.stack ?? e}\n`);
    return new Response(null, { status: 500 });
  },
  async fetch(req, srv) {
    const url = new URL(req.url);
    const path = url.pathname + url.search;
    const client = srv.requestIP(req)?.address ?? "-";
    if (req.method !== "GET" && req.method !== "POST") return unsupportedMethod(req.method, client, path);
    const { status, body } = req.method === "GET" ? doGet(req, path, client, db) : await doPost(req, path, client, db);
    log(client, `"${req.method} ${path} HTTP/1.1" ${status} -`);
    return new Response(dumps(body), {
      status,
      headers: { "Content-Type": "application/json", Server: "puls-sqlite-receiver/1" },
    });
  },
});
console.log(`puls-sqlite-receiver listening on ${bind_}:${server.port}`);
