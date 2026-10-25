#!/usr/bin/env bun
// Read-only maps MCP server for Claude, on the macmini (Streamable HTTP, JSON responses).
//
// One endpoint gives every Claude on the tailnet the map knowledge Google Maps would otherwise
// supply, from sources that stay ours or open (see the maps memory for why each was chosen):
//
//     geocode / reverse_geocode   local photon via photon-proxy (:2323) + GSI address search
//                                 + Overture addresses (block-level 番地) from the local SQLite
//     nearby_places               Overture places (Japan) from the local SQLite
//     apple_search / apple_route  Apple Maps Server API (key from sops, 25k calls/day)
//     transit_route               Transitous (open MOTIS instance; Google's API returns nothing in Japan)
//     web_search                  self-hosted SearXNG; google + google cse is an anonymous Google search
//     hotpepper                   Hot Pepper Gourmet (restaurants with opening hours / closed days;
//                                 key from sops, free, needs the credit shown)
//     weather                     Open-Meteo
//
// Nothing beyond Bun: the ES256 JWT for Apple is signed with node:crypto, and the Overture
// database is plain bun:sqlite. Nothing here writes anywhere.
//
//     bun server.ts              serve on :2324 (POST /mcp)
//     bun server.ts --selftest   call every tool against the live services
//
// Ported from server.py. The MCP protocol is hand-rolled on purpose (no SDK). Replies are
// serialised the way Python's json.dumps did (", " / ": " separators, floats keep their ".0"),
// and tool errors keep the Python-style "bad request: TypeError(...)" / "<tool> failed: ..." texts.
import { sign } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { Database } from "bun:sqlite";

const PORT = 2324;
const HOME = homedir();
const PHOTON = process.env.PHOTON_URL ?? "http://127.0.0.1:2323";
const SEARXNG = process.env.SEARXNG_URL ?? "https://search.gapul.net";
const TRANSITOUS = "https://api.transitous.org/api/v5/plan";
const OVERTURE_DB = `${HOME}/.local/share/overture/japan.sqlite`;
// Under launchd these come from the daemon's environment (nix/hosts/macmini.nix, keys from sops);
// the fallback env file lets the selftest run by hand.
const APPLE_ENV = `${HOME}/.config/apple-maps/env`;
const HOTPEPPER_KEY = process.env.HOTPEPPER_KEY_PATH ?? `${HOME}/.config/hotpepper/key`;
const HOTPEPPER_RANGES = [300, 500, 1000, 2000, 3000]; // the API takes range=1..5 for these metres
const UA = "gapul-maps-mcp/1.0 (+https://gapul.net)";
const TIMEOUT = 20;

// --- Python compatibility ---------------------------------------------------------------------
// A JSON float that happens to be integral (35.0) is kept as a Number object so it prints back
// as "35.0" like Python's float would; arithmetic on it works as usual.

type Json = any;

const pyFloat = (x: number): number => (Number.isInteger(x) ? (new Number(x) as number) : x);

// JSON.parse that remembers which numbers were written as floats.
function parseJson(text: string): Json {
  return JSON.parse(text, (_key, value, ctx?: { source?: string }) =>
    typeof value === "number" && ctx?.source && /[.eE]/.test(ctx.source) ? pyFloat(value) : value,
  );
}

function floatRepr(x: number): string {
  if (Number.isNaN(x)) return "NaN";
  if (!Number.isFinite(x)) return x > 0 ? "Infinity" : "-Infinity";
  if (x === 0) return Object.is(x, -0) ? "-0.0" : "0.0";
  const [mant, expStr] = x.toExponential().split("e");
  const exp = Number(expStr);
  if (exp < -4 || exp >= 16) {
    return `${mant}e${exp < 0 ? "-" : "+"}${String(Math.abs(exp)).padStart(2, "0")}`;
  }
  const s = x.toFixed(Math.max(0, (mant.split(".")[1]?.length ?? 0) - exp));
  return s.includes(".") ? s : `${s}.0`;
}

function numRepr(x: number | Number): string {
  if (x instanceof Number) return floatRepr(x.valueOf());
  return Number.isInteger(x) ? String(x) : floatRepr(x);
}

// json.dumps(value, ensure_ascii=False)
function dumps(v: Json): string {
  if (v === null || v === undefined) return "null";
  if (typeof v === "boolean") return v ? "true" : "false";
  if (typeof v === "number" || v instanceof Number) return numRepr(v);
  if (typeof v === "string") return JSON.stringify(v);
  if (Array.isArray(v)) return `[${v.map(dumps).join(", ")}]`;
  return `{${Object.entries(v)
    .map(([k, x]) => `${JSON.stringify(k)}: ${dumps(x)}`)
    .join(", ")}}`;
}

function strRepr(s: string): string {
  const q = s.includes("'") && !s.includes('"') ? '"' : "'";
  let out = "";
  for (const ch of s) {
    const c = ch.codePointAt(0) ?? 0;
    if (ch === "\\" || ch === q) out += `\\${ch}`;
    else if (ch === "\n") out += "\\n";
    else if (ch === "\r") out += "\\r";
    else if (ch === "\t") out += "\\t";
    else if (c < 0x20 || c === 0x7f) out += `\\x${c.toString(16).padStart(2, "0")}`;
    else out += ch;
  }
  return q + out + q;
}

// repr() of a JSON-shaped value
function repr(v: Json): string {
  if (v === null || v === undefined) return "None";
  if (typeof v === "boolean") return v ? "True" : "False";
  if (typeof v === "number" || v instanceof Number) {
    const s = numRepr(v);
    return s === "NaN" ? "nan" : s === "Infinity" ? "inf" : s === "-Infinity" ? "-inf" : s;
  }
  if (typeof v === "string") return strRepr(v);
  if (Array.isArray(v)) return `[${v.map(repr).join(", ")}]`;
  return `{${Object.entries(v)
    .map(([k, x]) => `${strRepr(k)}: ${repr(x)}`)
    .join(", ")}}`;
}

// str() as used by f-strings and urlencode
const str = (v: Json): string => (typeof v === "string" ? v : repr(v));

function truthy(v: Json): boolean {
  if (v instanceof Number) return v.valueOf() !== 0;
  if (Array.isArray(v)) return v.length > 0;
  if (v && typeof v === "object") return Object.keys(v).length > 0;
  return Boolean(v);
}

// urllib.parse.urlencode (quote_plus; only -._~ stay unescaped)
function urlencode(params: Record<string, Json>): string {
  const q = (s: string) =>
    encodeURIComponent(s)
      .replace(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`)
      .replace(/%20/g, "+");
  return Object.entries(params)
    .map(([k, v]) => `${q(k)}=${q(str(v))}`)
    .join("&");
}

// Python's round(): half to even, also at two decimals.
function pyRound(x: number): number {
  const f = Math.floor(x);
  if (x - f === 0.5) return f % 2 === 0 ? f : f + 1;
  return Math.round(x);
}

function pyRound2(x: number): number {
  // An exact tie at two decimals is m/8 with m odd; everything else toFixed gets right.
  const e = x * 8;
  if (Number.isInteger(e) && e % 2 !== 0) {
    const lo = Math.floor(x * 100);
    return pyFloat((lo % 2 === 0 ? lo : lo + 1) / 100);
  }
  return pyFloat(Number(x.toFixed(2)));
}

const chars = (s: string, n: number): string => Array.from(s).slice(0, n).join("");

// A Python exception, kept as its repr. `bad` ones (KeyError, TypeError) answer "bad request".
class PyError extends Error {
  constructor(
    readonly repr: string,
    readonly bad = false,
    readonly detail = "",
  ) {
    super(repr);
  }
}

const keyError = (k: string) => new PyError(`KeyError(${strRepr(k)})`, true);
const typeError = (m: string) => new PyError(`TypeError(${strRepr(m)})`, true);

// d[k] with Python's KeyError
function K(d: Json, k: string): Json {
  if (d == null || typeof d !== "object" || !(k in d)) throw keyError(k);
  return d[k];
}

// d.get(k, default)
const G = (d: Json, k: string, dflt: Json = null): Json =>
  d != null && typeof d === "object" && k in d ? d[k] : dflt;

// seq[:limit]
function head<T>(xs: T[], limit: Json): T[] {
  if (limit == null) return xs;
  if (typeof limit === "boolean") return xs.slice(0, Number(limit));
  if (typeof limit !== "number" || !Number.isInteger(limit)) {
    throw typeError("slice indices must be integers or None or have an __index__ method");
  }
  return xs.slice(0, limit);
}

function fetchError(e: unknown): PyError {
  if (e instanceof PyError) return e;
  const err = e as { name?: string; code?: string; message?: string };
  if (err?.name === "TimeoutError" || err?.name === "AbortError") {
    return new PyError("TimeoutError('timed out')");
  }
  if (err?.code === "ConnectionRefused") {
    return new PyError("URLError(ConnectionRefusedError(61, 'Connection refused'))");
  }
  return new PyError(`URLError(${strRepr(String(err?.message ?? e))})`);
}

async function httpJson(url: string, headers: Record<string, string> = {}): Promise<Json> {
  let res: Response;
  let text: string;
  try {
    res = await fetch(url, {
      headers: { "User-Agent": UA, ...headers },
      signal: AbortSignal.timeout(TIMEOUT * 1000),
    });
    text = await res.text();
  } catch (e) {
    throw fetchError(e);
  }
  if (res.status < 200 || res.status >= 300) {
    throw new PyError(`<HTTPError ${res.status}: ${strRepr(res.statusText)}>`, false, chars(text, 300));
  }
  try {
    return parseJson(text);
  } catch (e) {
    throw new PyError(`JSONDecodeError(${strRepr((e as Error).message)})`);
  }
}

const radians = (d: number): number => d * (Math.PI / 180);

function km(lat1: number, lon1: number, lat2: number, lon2: number): number {
  return Math.hypot(lat2 - lat1, (lon2 - lon1) * Math.cos(radians(lat1))) * 111.2;
}

function readText(path: string): string {
  try {
    return readFileSync(path, "utf8");
  } catch (e) {
    const code = (e as { code?: string }).code;
    if (code === "ENOENT") throw new PyError("FileNotFoundError(2, 'No such file or directory')");
    if (code === "EACCES") throw new PyError("PermissionError(13, 'Permission denied')");
    throw new PyError(`OSError(${strRepr(String(e))})`);
  }
}

// --- Apple Maps Server API -------------------------------------------------------------------

let apple_: { token: string | null; until: number } = { token: null, until: 0 };
let appleInflight: Promise<string> | null = null;

function appleEnv(): Record<string, string | undefined> {
  if ("APPLE_MAPS_KEY_PATH" in process.env) return process.env;
  const env: Record<string, string> = {};
  for (const line of readText(APPLE_ENV).split(/\r\n|[\n\r\v\f\x1c-\x1e\x85\u2028\u2029]/)) {
    const i = line.indexOf("=");
    if (i >= 0) env[line.slice(0, i)] = line.slice(i + 1);
  }
  return env;
}

const b64 = (b: Uint8Array | string): string => Buffer.from(b).toString("base64url");

async function mintAppleToken(): Promise<string> {
  const env = appleEnv();
  const need = (k: string): string => {
    const v = env[k];
    if (v === undefined) throw keyError(k);
    return v;
  };
  const now = Math.floor(Date.now() / 1000);
  const head_ = b64(dumps({ alg: "ES256", kid: need("APPLE_MAPS_KEY_ID"), typ: "JWT" }));
  const body = b64(dumps({ iss: need("APPLE_MAPS_TEAM_ID"), iat: now, exp: now + 1800 }));
  const key = readText(need("APPLE_MAPS_KEY_PATH"));
  let sig: Buffer;
  try {
    // ES256 wants the raw r || s, not DER.
    sig = sign("sha256", Buffer.from(`${head_}.${body}`), { key, dsaEncoding: "ieee-p1363" });
  } catch (e) {
    throw new PyError(`ValueError(${strRepr((e as Error).message)})`);
  }
  const tok = await httpJson("https://maps-api.apple.com/v1/token", {
    Authorization: `Bearer ${head_}.${body}.${b64(sig)}`,
  });
  const token = K(tok, "accessToken");
  apple_ = { token, until: Date.now() / 1000 + Number(G(tok, "expiresInSeconds", 1800)) - 120 };
  return token;
}

async function appleToken(): Promise<string> {
  if (apple_.token && Date.now() / 1000 < apple_.until) return apple_.token;
  // One mint at a time, like the lock in the Python version.
  appleInflight ??= mintAppleToken().finally(() => {
    appleInflight = null;
  });
  return appleInflight;
}

async function apple(path: string, params: Record<string, Json>): Promise<Json> {
  const q = urlencode(Object.fromEntries(Object.entries(params).filter(([, v]) => v != null)));
  return httpJson(`https://maps-api.apple.com${path}?${q}`, {
    Authorization: `Bearer ${await appleToken()}`,
  });
}

function placeBrief(p: Json): Json {
  return {
    name: G(p, "name"),
    category: G(p, "poiCategory"),
    address: (G(p, "formattedAddressLines") || []).map(str).join(" "),
    lat: G(G(p, "coordinate", {}), "latitude"),
    lon: G(G(p, "coordinate", {}), "longitude"),
  };
}

async function appleSearch(a: Json): Promise<Json> {
  const { query, near_lat = null, near_lon = null, limit = 5 } = a;
  const near = near_lat != null && near_lon != null ? `${str(near_lat)},${str(near_lon)}` : null;
  const res = await apple("/v1/search", { q: query, searchLocation: near, lang: "ja-JP" });
  return head(G(res, "results", []), limit).map(placeBrief);
}

async function appleRoute(a: Json): Promise<Json> {
  const { from_lat, from_lon, to_lat, to_lon, mode = "Automobile", depart_at = null } = a;
  const res = await apple("/v1/directions", {
    origin: `${str(from_lat)},${str(from_lon)}`,
    destination: `${str(to_lat)},${str(to_lon)}`,
    transportType: mode,
    departureDate: depart_at,
    lang: "ja-JP",
    requestsAlternateRoutes: "true",
  });
  const steps: Json[] = G(res, "steps", []);
  return (G(res, "routes", []) as Json[]).slice(0, 3).map((r) => ({
    name: G(r, "name"),
    distance_km: pyRound2(G(r, "distanceMeters", 0) / 1000),
    duration_min: pyRound(G(r, "durationSeconds", 0) / 60),
    has_tolls: G(r, "hasTolls"),
    steps: (G(r, "stepIndexes", []) as number[])
      .filter((i) => i < steps.length && truthy(G(steps[i], "instructions")))
      .map((i) => G(steps[i], "instructions"))
      .slice(0, 25),
  }));
}

// --- photon / GSI / Overture -----------------------------------------------------------------

async function geocode(a: Json): Promise<Json> {
  const { query, near_lat = null, near_lon = null, limit = 5 } = a;
  const params: Record<string, Json> = { q: query, limit };
  if (near_lat != null && near_lon != null) Object.assign(params, { lat: near_lat, lon: near_lon });
  const out: { photon: Json[]; gsi: Json[] } = { photon: [], gsi: [] };
  for (const f of G(await httpJson(`${PHOTON}/api?${urlencode(params)}`), "features", [])) {
    const p = K(f, "properties");
    const coords = K(K(f, "geometry"), "coordinates");
    out.photon.push({
      name: G(p, "name"),
      kind: `${str(G(p, "osm_key"))}=${str(G(p, "osm_value"))}`,
      address: [G(p, "state"), G(p, "city"), G(p, "street"), G(p, "housenumber")]
        .filter(truthy)
        .join(" "),
      lat: coords[1],
      lon: coords[0],
    });
  }
  try {
    const gsi = await httpJson(
      `https://msearch.gsi.go.jp/address-search/AddressSearch?${urlencode({ q: query })}`,
    );
    out.gsi = head(gsi, limit).map((g: Json) => ({
      title: K(K(g, "properties"), "title"),
      lat: K(K(g, "geometry"), "coordinates")[1],
      lon: K(K(g, "geometry"), "coordinates")[0],
    }));
  } catch (e) {
    // GSI is a second opinion for addresses; photon already answered
    if (e instanceof PyError && e.bad && !e.repr.startsWith("KeyError")) throw e;
  }
  return out;
}

function db(): Database {
  try {
    return new Database(OVERTURE_DB, { readonly: true });
  } catch (e) {
    throw new PyError(`OperationalError(${strRepr((e as Error).message)})`);
  }
}

function query(sql: string, args: Json[]): Record<string, Json>[] {
  const con = db();
  try {
    const stmt = con.query(sql);
    const rows = stmt.all(...args) as Record<string, Json>[];
    // A REAL-affinity column always comes back as a Python float, 1.0 included.
    const real = stmt.columnNames.filter((_, i) =>
      /REAL|FLOA|DOUB/i.test(stmt.declaredTypes[i] ?? ""),
    );
    for (const row of rows) {
      for (const c of real) if (typeof row[c] === "number") row[c] = pyFloat(row[c]);
    }
    return rows;
  } catch (e) {
    throw new PyError(`OperationalError(${strRepr((e as Error).message)})`);
  } finally {
    con.close();
  }
}

function box(lat: number, lon: number, radiusM: number): number[] {
  const dlat = radiusM / 111200;
  const dlon = dlat / Math.max(Math.cos(radians(lat)), 0.01);
  return [lat - dlat, lat + dlat, lon - dlon, lon + dlon];
}

const minBy = <T>(xs: T[], key: (x: T) => number): T =>
  xs.reduce((best, x) => (key(x) < key(best) ? x : best));

async function reverseGeocode(a: Json): Promise<Json> {
  const { lat, lon } = a;
  const out: Json = { photon: null, nearest_address: null };
  const feats = G(await httpJson(`${PHOTON}/reverse?${urlencode({ lat, lon })}`), "features", []);
  if (truthy(feats)) {
    const p = K(feats[0], "properties");
    out.photon = Object.fromEntries(
      ["name", "state", "city", "street", "housenumber", "postcode", "country"].map((k) => [
        k,
        G(p, k),
      ]),
    );
  }
  if (existsSync(OVERTURE_DB)) {
    const rows = query(
      "SELECT pref, city, street, number, lat, lon FROM addresses " +
        "WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?",
      box(lat, lon, 60),
    );
    if (rows.length) {
      const r = minBy(rows, (r) => km(lat, lon, r.lat, r.lon));
      out.nearest_address = {
        address: `${r.pref || ""}${r.city || ""}${r.street || ""}${r.number || ""}`,
        distance_m: pyRound(km(lat, lon, r.lat, r.lon) * 1000),
      };
    }
  }
  return out;
}

async function nearbyPlaces(a: Json): Promise<Json> {
  const {
    lat,
    lon,
    radius_m = 500,
    keyword = null,
    category = null,
    min_confidence = 0.7,
    limit = 20,
  } = a;
  if (!existsSync(OVERTURE_DB)) {
    throw new PyError(
      "RuntimeError('Overture database not built yet (~/.local/share/overture/build.sh)')",
    );
  }
  let sql =
    "SELECT name, category, confidence, phone, website, address, brand, lat, lon FROM places " +
    "WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ? AND confidence >= ?";
  const args: Json[] = [...box(lat, lon, radius_m), Number(min_confidence)];
  if (truthy(keyword)) {
    sql += " AND (name LIKE ? OR brand LIKE ?)";
    args.push(`%${str(keyword)}%`, `%${str(keyword)}%`);
  }
  if (truthy(category)) {
    sql += " AND (category LIKE ? OR taxonomy LIKE ?)";
    args.push(`%${str(category)}%`, `%${str(category)}%`);
  }
  const rows = query(sql, args)
    .map((r) => ({ ...r, distance_m: pyRound(km(lat, lon, r.lat, r.lon) * 1000) }))
    .filter((r) => r.distance_m <= radius_m);
  return head(
    rows.sort((x, y) => x.distance_m - y.distance_m),
    limit,
  );
}

// --- transit / search / weather --------------------------------------------------------------

async function transitRoute(a: Json): Promise<Json> {
  const { from_lat, from_lon, to_lat, to_lon, time_iso = null, arrive_by = false, limit = 4 } = a;
  const params: Record<string, Json> = {
    fromPlace: `${str(from_lat)},${str(from_lon)}`,
    toPlace: `${str(to_lat)},${str(to_lon)}`,
  };
  if (truthy(time_iso)) {
    Object.assign(params, { time: time_iso, arriveBy: String(truthy(arrive_by)) });
  }
  const res = await httpJson(`${TRANSITOUS}?${urlencode(params)}`);
  const out = head(G(res, "itineraries") || [], limit).map((it: Json) => ({
    minutes: pyRound(G(it, "duration", 0) / 60),
    depart: G(it, "startTime"),
    arrive: G(it, "endTime"),
    transfers: G(it, "transfers"),
    legs: (G(it, "legs", []) as Json[]).map((seg) => {
      const leg: Json = {
        mode: G(seg, "mode"),
        from: G(G(seg, "from") || {}, "name"),
        to: G(G(seg, "to") || {}, "name"),
        depart: G(seg, "startTime"),
        arrive: G(seg, "endTime"),
        minutes: pyRound(G(seg, "duration", 0) / 60),
      };
      if (G(seg, "mode") !== "WALK") {
        Object.assign(leg, {
          line: G(seg, "routeShortName"),
          agency: G(seg, "agencyName"),
          headsign: G(seg, "headsign"),
        });
      }
      return leg;
    }),
  }));
  return { itineraries: out, attribution: "https://transitous.org/sources/" };
}

async function webSearch(a: Json): Promise<Json> {
  const { query, engines = "google,google cse", limit = 8 } = a;
  const res = await httpJson(`${SEARXNG}/search?${urlencode({ q: query, format: "json", engines })}`);
  return {
    results: head(G(res, "results", []), limit).map((r: Json) => ({
      title: G(r, "title"),
      url: G(r, "url"),
      snippet: chars(G(r, "content") || "", 300),
      engine: G(r, "engine"),
    })),
    unresponsive: G(res, "unresponsive_engines"),
  };
}

async function hotpepper(a: Json): Promise<Json> {
  const { lat, lon, radius_m = 500, keyword = null, limit = 10 } = a;
  const key = readText(HOTPEPPER_KEY).trim();
  const i = HOTPEPPER_RANGES.findIndex((m) => radius_m <= m);
  const rng = i >= 0 ? i + 1 : HOTPEPPER_RANGES.length;
  const params: Record<string, Json> = {
    key,
    lat,
    lng: lon,
    range: rng,
    count: Math.min(limit, 100),
    format: "json",
    order: 4,
  }; // 4 = recommended
  if (truthy(keyword)) params.keyword = keyword;
  const res = K(
    await httpJson(`https://webservice.recruit.co.jp/hotpepper/gourmet/v1/?${urlencode(params)}`),
    "results",
  );
  if ("error" in res) throw new PyError(`RuntimeError(${repr(res.error)})`);
  return {
    shops: (G(res, "shop", []) as Json[]).map((s) => ({
      name: K(s, "name"),
      genre: K(K(s, "genre"), "name"),
      catch: G(s, "catch"),
      open: G(s, "open"),
      closed: G(s, "close"),
      budget: G(G(s, "budget", {}), "name"),
      address: G(s, "address"),
      access: G(s, "mobile_access"),
      lat: G(s, "lat"),
      lon: G(s, "lng"),
      url: G(G(s, "urls", {}), "pc"),
      distance_m: pyRound(km(lat, lon, Number(K(s, "lat")), Number(K(s, "lng"))) * 1000),
    })),
    available: G(res, "results_available"),
    credit: "Powered by ホットペッパーグルメ Webサービス (http://webservice.recruit.co.jp/)",
  };
}

async function weather(a: Json): Promise<Json> {
  const { lat, lon, days = 2 } = a;
  const q = urlencode({
    latitude: lat,
    longitude: lon,
    timezone: "Asia/Tokyo",
    forecast_days: days,
    hourly: "temperature_2m,precipitation_probability,precipitation,weather_code",
    daily: "temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code",
  });
  return httpJson(`https://api.open-meteo.com/v1/forecast?${q}`);
}

// --- MCP plumbing ----------------------------------------------------------------------------

interface Tool {
  fn: (args: Json) => Promise<Json>;
  // The Python signature: every parameter, and how many of them come first without a default.
  params: string[];
  required: number;
  description: string;
  properties: Record<string, Json>;
  requiredArgs: string[];
}

const NUM = { type: "number" };
const STR = { type: "string" };
const TOOLS: Record<string, Tool> = {
  geocode: {
    fn: geocode,
    params: ["query", "near_lat", "near_lon", "limit"],
    required: 1,
    description:
      "Place name or address → coordinates. Local photon (OSM, Japanese) plus the GSI " +
      "official address search. Pass near_lat/near_lon to bias towards an area.",
    properties: { query: STR, near_lat: NUM, near_lon: NUM, limit: { type: "integer" } },
    requiredArgs: ["query"],
  },
  reverse_geocode: {
    fn: reverseGeocode,
    params: ["lat", "lon"],
    required: 2,
    description:
      "Coordinates → address. photon gives the 町丁目; Overture adds the " +
      "nearest block-level 番地 within 60 m.",
    properties: { lat: NUM, lon: NUM },
    requiredArgs: ["lat", "lon"],
  },
  nearby_places: {
    fn: nearbyPlaces,
    params: ["lat", "lon", "radius_m", "keyword", "category", "min_confidence", "limit"],
    required: 2,
    description:
      "Shops, restaurants, cafes etc. around a point from Overture Maps " +
      "(Japan, ~2.9M places, has phone/website, no opening hours or reviews). Filter by keyword " +
      "(name/brand) or category (e.g. cafe, restaurant, coffee_shop, bar).",
    properties: {
      lat: NUM,
      lon: NUM,
      radius_m: NUM,
      keyword: STR,
      category: STR,
      min_confidence: NUM,
      limit: { type: "integer" },
    },
    requiredArgs: ["lat", "lon"],
  },
  apple_search: {
    fn: appleSearch,
    params: ["query", "near_lat", "near_lon", "limit"],
    required: 1,
    description:
      "Apple Maps place search (name, category, address, coordinates). Good " +
      "general-purpose place lookup.",
    properties: { query: STR, near_lat: NUM, near_lon: NUM, limit: { type: "integer" } },
    requiredArgs: ["query"],
  },
  apple_route: {
    fn: appleRoute,
    params: ["from_lat", "from_lon", "to_lat", "to_lon", "mode", "depart_at"],
    required: 4,
    description:
      "Apple Maps directions with traffic-aware duration. mode: Automobile, Walking " +
      "or Cycling (no transit — use transit_route). depart_at: ISO 8601 UTC.",
    properties: {
      from_lat: NUM,
      from_lon: NUM,
      to_lat: NUM,
      to_lon: NUM,
      mode: { type: "string", enum: ["Automobile", "Walking", "Cycling"] },
      depart_at: STR,
    },
    requiredArgs: ["from_lat", "from_lon", "to_lat", "to_lon"],
  },
  transit_route: {
    fn: transitRoute,
    params: ["from_lat", "from_lon", "to_lat", "to_lon", "time_iso", "arrive_by", "limit"],
    required: 4,
    description:
      "Public transport itineraries in Japan (Tokyo Metro, Toei, JR East, buses) " +
      "via Transitous. time_iso: ISO 8601 with offset; arrive_by makes it an arrival time. " +
      "Sometimes prefers a bus leg oddly; sanity-check.",
    properties: {
      from_lat: NUM,
      from_lon: NUM,
      to_lat: NUM,
      to_lon: NUM,
      time_iso: STR,
      arrive_by: { type: "boolean" },
      limit: { type: "integer" },
    },
    requiredArgs: ["from_lat", "from_lon", "to_lat", "to_lon"],
  },
  web_search: {
    fn: webSearch,
    params: ["query", "engines", "limit"],
    required: 1,
    description:
      "Web search through the self-hosted SearXNG. The default engines (google, google cse) are an " +
      "anonymous Google search (no account, only the home IP is visible); plain google is often " +
      "CAPTCHA-suspended for a while and google cse then answers. Use for opening hours, temporary closures, " +
      "reviews (tabelog for restaurants).",
    properties: { query: STR, engines: STR, limit: { type: "integer" } },
    requiredArgs: ["query"],
  },
  hotpepper: {
    fn: hotpepper,
    params: ["lat", "lon", "radius_m", "keyword", "limit"],
    required: 2,
    description:
      "Restaurants around a point from Hot Pepper Gourmet, with opening hours (open) and " +
      "closed days (closed) as free text, budget and access. Best source for restaurant hours; " +
      "covers listed restaurants only. radius_m is rounded up to 300/500/1000/2000/3000.",
    properties: { lat: NUM, lon: NUM, radius_m: NUM, keyword: STR, limit: { type: "integer" } },
    requiredArgs: ["lat", "lon"],
  },
  weather: {
    fn: weather,
    params: ["lat", "lon", "days"],
    required: 2,
    description: "Weather forecast (Open-Meteo), hourly and daily, Asia/Tokyo.",
    properties: { lat: NUM, lon: NUM, days: { type: "integer" } },
    requiredArgs: ["lat", "lon"],
  },
};

function toolsList(): Json[] {
  return Object.entries(TOOLS).map(([n, t]) => ({
    name: n,
    description: t.description,
    annotations: { readOnlyHint: true },
    inputSchema: { type: "object", properties: t.properties, required: t.requiredArgs },
  }));
}

// fn(**args) with Python's TypeErrors for a bad mapping, unknown or missing arguments.
function bind(name: string, tool: Tool, args: Json): Record<string, Json> {
  if (args === null || typeof args !== "object" || Array.isArray(args)) {
    const type = Array.isArray(args)
      ? "list"
      : typeof args === "string"
        ? "str"
        : typeof args === "boolean"
          ? "bool"
          : Number.isInteger(args) && !(args instanceof Number)
            ? "int"
            : "float";
    throw typeError(`__main__.${name}() argument after ** must be a mapping, not ${type}`);
  }
  for (const k of Object.keys(args)) {
    if (!tool.params.includes(k)) {
      throw typeError(`${name}() got an unexpected keyword argument '${k}'`);
    }
  }
  const missing = tool.params.slice(0, tool.required).filter((p) => !(p in args));
  if (missing.length) {
    const q = missing.map((m) => `'${m}'`);
    const list =
      q.length === 1
        ? q[0]
        : q.length === 2
          ? `${q[0]} and ${q[1]}`
          : `${q.slice(0, -1).join(", ")}, and ${q[q.length - 1]}`;
    const noun = missing.length === 1 ? "argument" : "arguments";
    throw typeError(`${name}() missing ${missing.length} required positional ${noun}: ${list}`);
  }
  return args;
}

const INSTRUCTIONS =
  "Read-only map tools: geocoding, nearby places (Overture), Apple Maps search and " +
  "driving/walking/cycling routes, Japanese transit (Transitous), anonymous web " +
  "search, restaurant opening hours (Hot Pepper), weather. The user's own location history is in the separate dawarich MCP.";

async function handle(msg: Json): Promise<Json> {
  const method = G(msg, "method");
  const mid = G(msg, "id");
  if (mid == null) return null; // notification
  let result: Json;
  if (method === "initialize") {
    result = {
      protocolVersion: G(G(msg, "params", {}), "protocolVersion", "2025-06-18"),
      capabilities: { tools: {} },
      serverInfo: { name: "maps", version: "1.0" },
      instructions: INSTRUCTIONS,
    };
  } else if (method === "ping") {
    result = {};
  } else if (method === "tools/list") {
    result = { tools: toolsList() };
  } else if (method === "tools/call") {
    // Python raised here and dropped the connection; answer as JSON-RPC says to.
    const p = G(msg, "params");
    if (p === null || typeof p !== "object" || Array.isArray(p) || !("name" in p)) {
      return { jsonrpc: "2.0", id: mid, error: { code: -32602, message: "params.name is required" } };
    }
    const name = K(K(msg, "params"), "name");
    const raw = G(msg.params, "arguments");
    const args = truthy(raw) ? raw : {};
    try {
      if (typeof name !== "string" || !Object.hasOwn(TOOLS, name)) throw keyError(String(name));
      const tool = TOOLS[name];
      const data = await tool.fn(bind(name, tool, args));
      result = { content: [{ type: "text", text: dumps(data) }] };
    } catch (e) {
      const err = e instanceof PyError ? e : new PyError(`${(e as Error).name}(${strRepr(String((e as Error).message))})`);
      result = err.bad
        ? { content: [{ type: "text", text: `bad request: ${err.repr}` }], isError: true }
        : {
            content: [{ type: "text", text: `${name} failed: ${err.repr} ${err.detail}` }],
            isError: true,
          };
    }
  } else {
    return { jsonrpc: "2.0", id: mid, error: { code: -32601, message: `unknown method ${str(method)}` } };
  }
  return { jsonrpc: "2.0", id: mid, result };
}

// --- HTTP, shaped like Python's BaseHTTPRequestHandler -----------------------------------------

const REASONS: Record<number, [string, string]> = {
  400: ["Bad Request", "Bad request syntax or unsupported method"],
  404: ["Not Found", "Nothing matches the given URI"],
  501: ["Not Implemented", "Server does not support this operation"],
};

function sendError(client: string, code: number, message?: string): Response {
  const [reason, explain] = REASONS[code];
  const msg = message ?? reason;
  console.error(`${client} code ${code}, message ${msg}`);
  const body =
    '<!DOCTYPE HTML>\n<html lang="en">\n    <head>\n        <meta charset="utf-8">\n' +
    "        <title>Error response</title>\n    </head>\n    <body>\n" +
    "        <h1>Error response</h1>\n" +
    `        <p>Error code: ${code}</p>\n` +
    `        <p>Message: ${msg}.</p>\n` +
    `        <p>Error code explanation: ${code} - ${explain}.</p>\n` +
    "    </body>\n</html>\n";
  return new Response(body, {
    status: code,
    headers: { "Content-Type": "text/html;charset=utf-8", Connection: "close" },
  });
}

async function respond(req: Request, client: string): Promise<Response> {
  const url = new URL(req.url);
  const path = url.pathname + url.search;
  if (req.method === "GET") {
    return new Response(null, { status: 405 }); // no server-initiated stream; clients fall back to plain POST
  }
  if (req.method !== "POST") return sendError(client, 501, `Unsupported method (${strRepr(req.method)})`);
  if (path.replace(/\/+$/, "") !== "/mcp") return sendError(client, 404);
  let msg: Json;
  try {
    msg = parseJson(await req.text());
  } catch {
    return sendError(client, 400);
  }
  const reply = Array.isArray(msg)
    ? (await Promise.all(msg.map(handle))).filter(truthy)
    : await handle(msg);
  if (!truthy(reply)) return new Response(null, { status: 202 });
  return new Response(dumps(reply), { headers: { "Content-Type": "application/json" } });
}

function serve(port: number): void {
  Bun.serve({
    hostname: "0.0.0.0",
    port,
    idleTimeout: 0, // a tool call can take longer than Bun's default 10 s
    async fetch(req, server) {
      const url = new URL(req.url);
      const ip = server.requestIP(req)?.address.replace(/^::ffff:/, "") ?? "-";
      let res: Response;
      try {
        res = await respond(req, ip);
      } catch (e) {
        console.error(`${url.pathname}: ${(e as Error).stack ?? e}`);
        res = new Response(null, { status: 500 });
      }
      console.error(`${ip} "${req.method} ${url.pathname}${url.search} HTTP/1.1" ${res.status} -`);
      return res;
    },
  });
}

async function selftest(): Promise<void> {
  const assert = (ok: unknown, what: string) => {
    if (!truthy(ok)) throw new Error(`AssertionError: ${what}`);
  };
  const k = { lat: 35.6751, lon: 139.763 }; // 有楽町
  const h = { to_lat: 35.6896, to_lon: 139.7006 }; // 新宿
  const from = { from_lat: k.lat, from_lon: k.lon };
  assert((await geocode({ query: "日比谷公園" })).photon, "geocode");
  assert((await reverseGeocode(k)).photon, "reverse_geocode");
  if (existsSync(OVERTURE_DB)) {
    assert(await nearbyPlaces({ ...k, radius_m: 400, category: "cafe" }), "nearby_places");
  }
  assert(await appleSearch({ query: "日比谷公園", near_lat: k.lat, near_lon: k.lon }), "apple_search");
  assert((await appleRoute({ ...from, ...h }))[0].duration_min > 0, "apple_route");
  assert((await transitRoute({ ...from, ...h })).itineraries, "transit_route");
  assert((await webSearch({ query: "有楽町 カフェ" })).results, "web_search");
  assert((await weather(k)).hourly.time, "weather");
  if (existsSync(HOTPEPPER_KEY)) assert((await hotpepper(k)).shops, "hotpepper");
  const names = toolsList().map((t) => t.name);
  assert(names.join() === Object.keys(TOOLS).join(), "tools_list");
  console.log(`ok${existsSync(OVERTURE_DB) ? "" : " (nearby_places skipped: no Overture DB yet)"}`);
}

if (import.meta.main) {
  if (process.argv.length === 3 && process.argv[2] === "--selftest") {
    await selftest();
  } else {
    serve(PORT);
  }
}
