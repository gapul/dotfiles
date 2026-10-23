#!/usr/bin/env bun
// Photon-compatible proxy in front of the local photon, for Dawarich on the homeserver.
//
// Dawarich always asks photon for lang=en and reads only properties.city / street / housenumber.
// In Japan that gives "Koto" and "Bunkyo", files every Tokyo ward and Tokyo city under 東京都
// (photon puts the ward in `district`, which Dawarich never reads), and turns addresses into the
// nearest road name, because OSM Japan addresses by block, not by street. So for results in
// Japan this asks for the local language and moves the fields to where Dawarich looks; anywhere
// else the request goes through untouched, English and all.
//
// The ward can't always come from photon: around 足立区東和 the neighbourhood sits where the
// ward should (district=東和, city=東京都) and 足立区 appears nowhere in the hierarchy. So when
// city is only a prefecture, the municipality comes from MLIT's 大字・町丁目レベル位置参照情報
// (出典: 国土交通省) instead — the 町丁目 of the same name nearest to the feature. The 47
// prefecture CSVs (a few MB in all) are fetched into ~/.local/share/photon/isj on first start.
//
// The local photon only holds Japan, so a point abroad would come back with no name at all. Those
// are answered here from GeoNames' cities1000 (every town of 1,000 people or more, about 11 MB,
// fetched into ~/.local/share/photon/geonames on first start): the nearest town, its state and
// its country. That is town-level only, no street, but it stays on this machine and covers every
// country; a full photon index for one more country is tens of GB.
//
//     bun proxy.ts              serve on :2323, upstream photon on 127.0.0.1:2322
//     bun proxy.ts --selftest   check the Japanese rewrite against real photon output
//
// Ported from proxy.py. Rewritten answers are serialised the way Python's json.dumps did
// (", " / ": " separators, floats keep their ".0"), so Dawarich sees the same bytes as before.
// The two zip formats are read with a small reader over node:zlib, the CSVs decoded as
// Shift_JIS (WHATWG's Shift_JIS is the cp932 superset the MLIT files use).
import { existsSync, mkdirSync, readFileSync, readdirSync, renameSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { inflateRawSync } from "node:zlib";

const PORT = 2323;
const UPSTREAM = "http://127.0.0.1:2322";
const PREFECTURE = /[都道府県]$/;
const ISJ_DIR = `${homedir()}/.local/share/photon/isj`;
const ISJ_URL = (code: string) => `https://nlftp.mlit.go.jp/isj/dls/data/19.0b/${code}000-19.0b.zip`; // 令和7年
const NEAREST_ONLY_KM = 3; // without a name match, trust the nearest 町丁目 only this close

type Town = [name: string, municipality: string, lat: number, lon: number];
type Towns = Map<string, Town[]>; // {prefecture: [(町丁目名, 市区町村名, lat, lon)]}
const TOWNS: Towns = new Map();

const GEONAMES_DIR = `${homedir()}/.local/share/photon/geonames`;
const GEONAMES_URL = "https://download.geonames.org/export/dump/";
const JAPAN = [20.0, 46.0, 122.0, 154.0]; // lat min/max, lon min/max: what the local photon index covers
type Place = [name: string, state: string | null, country: string, cc: string, lat: number, lon: number];
type Cells = Map<string, Place[]>; // {(floor(lat), floor(lon)): [(name, state, country, countrycode, lat, lon)]}
const PLACES: Cells = new Map();

type Json = any; // photon's JSON is untyped

// --- Python compatibility ---------------------------------------------------------------------

// A JSON float that happens to be integral (35.0) is kept as a Number object so it prints back
// as "35.0" like Python's float would.
const pyFloat = (x: number): number => (Number.isInteger(x) ? (new Number(x) as number) : x);

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

// json.dumps(value, ensure_ascii=asciiOnly)
function dumps(v: Json, asciiOnly = false): string {
  if (v === null || v === undefined) return "null";
  if (typeof v === "boolean") return v ? "true" : "false";
  if (v instanceof Number) return floatRepr(v.valueOf());
  if (typeof v === "number") return Number.isInteger(v) ? String(v) : floatRepr(v);
  if (typeof v === "string") {
    const s = JSON.stringify(v);
    return asciiOnly
      ? s.replace(/[\u007f-\uffff]/g, (c) => `\\u${c.charCodeAt(0).toString(16).padStart(4, "0")}`)
      : s;
  }
  if (Array.isArray(v)) return `[${v.map((x) => dumps(x, asciiOnly)).join(", ")}]`;
  return `{${Object.entries(v)
    .map(([k, x]) => `${dumps(k, asciiOnly)}: ${dumps(x, asciiOnly)}`)
    .join(", ")}}`;
}

const strRepr = (s: string): string => {
  const q = s.includes("'") && !s.includes('"') ? '"' : "'";
  return q + s.replace(/\\/g, "\\\\").replaceAll(q, `\\${q}`).replace(/\n/g, "\\n") + q;
};

// str.isdigit(): decimal digits plus the other Numeric_Type=Digit characters (², ①, ...).
const DIGITS =
  /^[\p{Nd}\u{B2}-\u{B3}\u{B9}\u{1369}-\u{1371}\u{19DA}\u{2070}\u{2074}-\u{2079}\u{2080}-\u{2089}\u{2460}-\u{2468}\u{2474}-\u{247C}\u{2488}-\u{2490}\u{24EA}\u{24F5}-\u{24FD}\u{24FF}\u{2776}-\u{277E}\u{2780}-\u{2788}\u{278A}-\u{2792}\u{10A40}-\u{10A43}\u{10E60}-\u{10E68}\u{11052}-\u{1105A}\u{1F100}-\u{1F10A}]+$/u;

const truthy = (v: Json): boolean =>
  Array.isArray(v) ? v.length > 0 : v instanceof Number ? v.valueOf() !== 0 : Boolean(v);

// urllib.parse.quote_plus
const quotePlus = (s: string): string =>
  encodeURIComponent(s)
    .replace(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`)
    .replace(/%20/g, "+");

// urllib.parse.unquote_plus (errors="replace")
const unquotePlus = (s: string): string =>
  s
    .replace(/\+/g, " ")
    .replace(/(?:%[0-9A-Fa-f]{2})+/g, (run) =>
      new TextDecoder().decode(
        Uint8Array.from(run.slice(1).split("%"), (h) => Number.parseInt(h, 16)),
      ),
    );

type Query = Map<string, string[]>;

// urllib.parse.parse_qs: blank values are dropped
function parseQs(qs: string): Query {
  const out: Query = new Map();
  for (const nv of qs.split("&")) {
    const i = nv.indexOf("=");
    if (!nv || i < 0 || i === nv.length - 1) continue;
    const k = unquotePlus(nv.slice(0, i));
    const v = unquotePlus(nv.slice(i + 1));
    out.set(k, [...(out.get(k) ?? []), v]);
  }
  return out;
}

// urllib.parse.urlencode(query, doseq=True)
const urlencode = (query: Query): string =>
  [...query].flatMap(([k, vs]) => vs.map((v) => `${quotePlus(k)}=${quotePlus(v)}`)).join("&");

// float(): decimal literals plus inf / nan, surrounding whitespace allowed
function pyFloatParse(s: string): number | null {
  const t = s.trim().replace(/(?<=\d)_(?=\d)/g, "");
  if (/^[+-]?(\d+\.?\d*|\.\d+)(e[+-]?\d+)?$/i.test(t)) return Number(t);
  const m = /^([+-]?)(inf|infinity|nan)$/i.exec(t);
  if (!m) return null;
  if (m[2].toLowerCase() === "nan") return Number.NaN;
  return m[1] === "-" ? -Infinity : Infinity;
}

// A Python-side failure: `repr` goes to the log, `str` into the 502 body.
class PyError extends Error {
  constructor(
    readonly repr: string,
    readonly str: string,
  ) {
    super(str);
  }
}

class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly body: Uint8Array,
    readonly repr: string,
  ) {
    super(repr);
  }
}

function urlError(e: unknown): PyError {
  if (e instanceof PyError) return e;
  const err = e as { name?: string; code?: string; message?: string };
  if (err?.name === "TimeoutError" || err?.name === "AbortError") {
    return new PyError("TimeoutError('timed out')", "timed out");
  }
  if (err?.code === "ConnectionRefused") {
    return new PyError(
      "URLError(ConnectionRefusedError(61, 'Connection refused'))",
      "<urlopen error [Errno 61] Connection refused>",
    );
  }
  const msg = String(err?.message ?? e);
  return new PyError(`URLError(${strRepr(msg)})`, `<urlopen error ${msg}>`);
}

// urllib.request.urlopen(url).read(), raising HttpError for anything but 2xx
async function urlopen(url: string, timeoutSeconds: number): Promise<[number, Uint8Array]> {
  let res: Response;
  let body: Uint8Array;
  try {
    res = await fetch(url, { signal: AbortSignal.timeout(timeoutSeconds * 1000) });
    body = new Uint8Array(await res.arrayBuffer());
  } catch (e) {
    throw urlError(e);
  }
  if (res.status < 200 || res.status >= 300) {
    throw new HttpError(res.status, body, `<HTTPError ${res.status}: ${strRepr(res.statusText)}>`);
  }
  return [res.status, body];
}

// --- zip (just enough for the MLIT and GeoNames archives) ----------------------------------------

const badZip = () => new PyError("BadZipFile('File is not a zip file')", "File is not a zip file");

function zipMembers(buf: Uint8Array): Map<string, () => Uint8Array> {
  const view = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  let eocd = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 22 - 0xffff); i--) {
    if (view.getUint32(i, true) === 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw badZip();
  const members = new Map<string, () => Uint8Array>();
  let p = view.getUint32(eocd + 16, true);
  for (let n = view.getUint16(eocd + 10, true); n > 0; n--) {
    if (view.getUint32(p, true) !== 0x02014b50) throw badZip();
    const method = view.getUint16(p + 10, true);
    const size = view.getUint32(p + 20, true);
    const nameLen = view.getUint16(p + 28, true);
    const local = view.getUint32(p + 42, true);
    const name = new TextDecoder().decode(buf.subarray(p + 46, p + 46 + nameLen));
    p += 46 + nameLen + view.getUint16(p + 30, true) + view.getUint16(p + 32, true);
    members.set(name, () => {
      const start = local + 30 + view.getUint16(local + 26, true) + view.getUint16(local + 28, true);
      const data = buf.subarray(start, start + size);
      if (method === 0) return data;
      if (method === 8) return inflateRawSync(data);
      throw new PyError(
        "NotImplementedError('That compression method is not supported')",
        "That compression method is not supported",
      );
    });
  }
  return members;
}

// csv.DictReader over the whole text
function csvDicts(text: string): Record<string, string>[] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let quoted = false;
  let i = 0;
  const endField = () => {
    row.push(field);
    field = "";
  };
  while (i < text.length) {
    const c = text[i];
    if (quoted) {
      if (c === '"' && text[i + 1] === '"') {
        field += '"';
        i += 2;
        continue;
      }
      if (c === '"') quoted = false;
      else field += c;
      i++;
    } else if (c === '"' && field === "") {
      quoted = true;
      i++;
    } else if (c === ",") {
      endField();
      i++;
    } else if (c === "\r" || c === "\n") {
      endField();
      rows.push(row);
      row = [];
      i += c === "\r" && text[i + 1] === "\n" ? 2 : 1;
    } else {
      field += c;
      i++;
    }
  }
  if (field || row.length) {
    endField();
    rows.push(row);
  }
  const nonEmpty = rows.filter((r) => !(r.length === 1 && r[0] === ""));
  const [header, ...body] = nonEmpty;
  return body.map((r) => Object.fromEntries(header.map((h, j) => [h, r[j]])));
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function loadTowns(directory = ISJ_DIR): Promise<Towns> {
  mkdirSync(directory, { recursive: true });
  for (let n = 1; n < 48; n++) {
    const code = String(n).padStart(2, "0");
    const path = `${directory}/${code}.csv`;
    if (existsSync(path)) continue;
    try {
      const [, zip] = await urlopen(ISJ_URL(code), 60);
      const members = zipMembers(zip);
      const member = [...members.keys()].find((m) => m.endsWith(".csv"));
      if (member === undefined) throw new PyError("StopIteration()", "");
      writeFileSync(`${directory}/${code}.tmp`, members.get(member)?.() ?? new Uint8Array());
      renameSync(`${directory}/${code}.tmp`, path);
    } catch (e) {
      // Serve without it; the next restart tries again.
      const r = e instanceof PyError || e instanceof HttpError ? e.repr : String(e);
      console.error(`isj ${code}: ${r}`);
    }
    await sleep(1000); // a government server
  }
  const towns: Towns = new Map();
  const sjis = new TextDecoder("shift_jis");
  for (const file of readdirSync(directory).filter((f) => f.endsWith(".csv"))) {
    for (const row of csvDicts(sjis.decode(readFileSync(`${directory}/${file}`)))) {
      const pref = row["都道府県名"];
      const list = towns.get(pref) ?? [];
      list.push([row["大字町丁目名"], row["市区町村名"], Number(row["緯度"]), Number(row["経度"])]);
      towns.set(pref, list);
    }
  }
  return towns;
}

const radians = (d: number): number => d * (Math.PI / 180);

function km(lat1: number, lon1: number, lat2: number, lon2: number): number {
  return Math.hypot(lat2 - lat1, (lon2 - lon1) * Math.cos(radians(lat1))) * 111.2;
}

const minBy = <T>(xs: T[], key: (x: T) => number): T | undefined =>
  xs.length ? xs.reduce((best, x) => (key(x) < key(best) ? x : best)) : undefined;

function municipality(
  prefecture: string,
  name: Json,
  lat: number,
  lon: number,
  towns: Towns,
): string | null {
  const rows = towns.get(prefecture) ?? [];
  const named = rows.filter((t) => t[0] === name);
  const best = minBy(named.length ? named : rows, (t) => km(lat, lon, t[2], t[3]));
  if (best && (named.length || km(lat, lon, best[2], best[3]) <= NEAREST_ONLY_KM)) return best[1];
  return null;
}

/** Rewrite one Japanese photon feature's properties in place. coords is [lon, lat]. */
function localize(props: Json, coords: Json = null, towns: Towns = TOWNS): Json {
  const city = props.city ?? null;
  const district = props.district ?? null;
  // 東京都/千代田区, 東京都/八王子市, 東京都/東和: city is only the prefecture.
  // 横浜市/西区 already has the municipality in city and stays as it is.
  if (truthy(city) && PREFECTURE.test(city)) {
    const found = truthy(coords)
      ? municipality(city, truthy(props.locality) ? props.locality : district, coords[1], coords[0], towns)
      : coords;
    if (truthy(found) || truthy(district)) {
      props.state = truthy(props.state) ? props.state : city;
      props.city = truthy(found) ? found : district;
    }
  }
  // A digits-only street is the 街区 number (Skytree: street "1", housenumber "2" = 1-2).
  // Anything else is just the nearest named road, which is not part of a Japanese address.
  const locality = props.locality;
  if (truthy(locality)) {
    const street = props.street;
    const block = truthy(street) && DIGITS.test(street) ? street : null;
    props.street = locality;
    props.housenumber = [block, props.housenumber ?? null].filter(truthy).join("-") || null;
  }
  return props;
}

function fetchUpstream(path: string, query: Query): Promise<[number, Uint8Array]> {
  return urlopen(`${UPSTREAM}${path}?${urlencode(query)}`, 10);
}

async function loadPlaces(directory = GEONAMES_DIR): Promise<Cells> {
  mkdirSync(directory, { recursive: true });

  async function get(name: string): Promise<string> {
    const path = `${directory}/${name}`;
    if (!existsSync(path)) {
      const [, body] = await urlopen(GEONAMES_URL + name, 120);
      const tmp = `${directory}/${name.replace(/\.[^.]*$/, "")}.tmp`;
      writeFileSync(tmp, body);
      renameSync(tmp, path);
    }
    return path;
  }

  async function rows(name: string): Promise<string[][]> {
    return readFileSync(await get(name), "utf8")
      .split(/\r\n|[\n\r\v\f\x1c-\x1e\x85\u2028\u2029]/)
      .filter((line) => line && !line.startsWith("#"))
      .map((line) => line.split("\t"));
  }

  const countries = new Map((await rows("countryInfo.txt")).map((f) => [f[0], f[4]]));
  const states = new Map((await rows("admin1CodesASCII.txt")).map((f) => [f[0], f[1]]));
  const cells: Cells = new Map();
  const member = zipMembers(readFileSync(await get("cities1000.zip"))).get("cities1000.txt");
  if (!member) {
    throw new PyError(
      "KeyError(\"There is no item named 'cities1000.txt' in the archive\")",
      "\"There is no item named 'cities1000.txt' in the archive\"",
    );
  }
  const text = new TextDecoder().decode(member());
  for (const line of text.split(/\r\n|\r|\n/)) {
    if (!line) continue;
    const f = line.split("\t");
    const lat = Number(f[4]);
    const lon = Number(f[5]);
    const cc = f[8];
    const key = `${Math.floor(lat)},${Math.floor(lon)}`;
    const list = cells.get(key) ?? [];
    list.push([f[2], states.get(`${cc}.${f[10]}`) ?? null, countries.get(cc) ?? cc, cc, lat, lon]);
    cells.set(key, list);
  }
  return cells;
}

function inJapan(lat: number, lon: number): boolean {
  return JAPAN[0] <= lat && lat <= JAPAN[1] && JAPAN[2] <= lon && lon <= JAPAN[3];
}

function floor(x: number): number {
  if (Number.isNaN(x)) {
    throw new PyError(
      "ValueError('cannot convert float NaN to integer')",
      "cannot convert float NaN to integer",
    );
  }
  if (!Number.isFinite(x)) {
    throw new PyError(
      "OverflowError('cannot convert float infinity to integer')",
      "cannot convert float infinity to integer",
    );
  }
  return Math.floor(x);
}

function nearestPlace(lat: number, lon: number, cells: Cells = PLACES): Place | null {
  // ponytail: 1-degree grid without wrap at ±180 longitude; fine unless you live on the date line.
  for (const r of [1, 3]) {
    const near: Place[] = [];
    for (let dy = -r; dy <= r; dy++) {
      for (let dx = -r; dx <= r; dx++) {
        near.push(...(cells.get(`${floor(lat) + dy},${floor(lon) + dx}`) ?? []));
      }
    }
    if (near.length) return minBy(near, (p) => km(lat, lon, p[4], p[5])) ?? null;
  }
  return null;
}

/** A photon-shaped answer naming the nearest GeoNames town, for points the local photon can't see. */
function placeFeatures(lat: number, lon: number, cells: Cells = PLACES): Json {
  const p = nearestPlace(lat, lon, cells);
  if (!p) return { type: "FeatureCollection", features: [] };
  const [name, state, country, cc, plat, plon] = p;
  const props = { type: "city", name, city: name, state, country, countrycode: cc };
  return {
    type: "FeatureCollection",
    features: [
      {
        type: "Feature",
        geometry: { type: "Point", coordinates: [pyFloat(plon), pyFloat(plat)] },
        properties: props,
      },
    ],
  };
}

const encoder = new TextEncoder();

async function handleGet(rawPath: string): Promise<[number, Uint8Array]> {
  const q = rawPath.indexOf("?");
  const path = (q < 0 ? rawPath : rawPath.slice(0, q)).split("#")[0];
  const query = parseQs(q < 0 ? "" : rawPath.slice(q + 1).split("#")[0]);
  const latS = query.get("lat")?.[0];
  const lonS = query.get("lon")?.[0];
  const lat = latS === undefined ? null : pyFloatParse(latS);
  const lon = lonS === undefined ? null : pyFloatParse(lonS);
  const located = lat !== null && lon !== null;
  try {
    if (located && !inJapan(lat, lon)) {
      return [200, encoder.encode(dumps(placeFeatures(lat, lon)))];
    }
    const localQuery: Query = new Map(query);
    localQuery.set("lang", ["default"]);
    let [status, body] = await fetchUpstream(path, localQuery);
    let parsed: Json;
    try {
      parsed = parseJson(new TextDecoder().decode(body));
    } catch (e) {
      throw new PyError(`JSONDecodeError(${strRepr((e as Error).message)})`, (e as Error).message);
    }
    const features: Json[] = (parsed?.features ?? null) || [];
    const props0 = features[0]?.properties;
    if (features.length && props0 === undefined) throw new PyError("KeyError('properties')", "'properties'");
    if (features.length && props0?.countrycode === "JP") {
      for (const f of features) {
        if (f.properties?.countrycode === "JP") {
          localize(f.properties, (f.geometry || {}).coordinates ?? null);
        }
      }
      body = encoder.encode(dumps({ type: "FeatureCollection", features }));
    } else {
      [status, body] = await fetchUpstream(path, query);
    }
    return [status, body];
  } catch (e) {
    if (e instanceof HttpError) return [e.status, e.body];
    const err = e instanceof PyError ? e : new PyError(String(e), String((e as Error)?.message ?? e));
    console.error(`upstream error for ${rawPath}: ${err.repr}`);
    return [502, encoder.encode(dumps({ message: err.str }, true))];
  }
}

function serve(port: number): void {
  Bun.serve({
    hostname: "0.0.0.0",
    port,
    idleTimeout: 0,
    async fetch(req) {
      // No access log: one line per GPS point otherwise.
      if (req.method !== "GET") {
        const body =
          '<!DOCTYPE HTML>\n<html lang="en">\n    <head>\n        <meta charset="utf-8">\n' +
          "        <title>Error response</title>\n    </head>\n    <body>\n" +
          "        <h1>Error response</h1>\n        <p>Error code: 501</p>\n" +
          `        <p>Message: Unsupported method (${strRepr(req.method)}).</p>\n` +
          "        <p>Error code explanation: 501 - Server does not support this operation.</p>\n" +
          "    </body>\n</html>\n";
        return new Response(body, {
          status: 501,
          headers: { "Content-Type": "text/html;charset=utf-8", Connection: "close" },
        });
      }
      const url = new URL(req.url);
      const [status, body] = await handleGet(url.pathname + url.search);
      return new Response(body, {
        status,
        headers: { "Content-Type": "application/json; charset=utf-8" },
      });
    },
  });
}

function selftest(): void {
  const eq = (got: unknown[], want: unknown[], what: unknown) => {
    if (JSON.stringify(got) !== JSON.stringify(want)) {
      throw new Error(`AssertionError: ${JSON.stringify(what)}`);
    }
  };
  const tokyo = localize({
    name: "東京",
    street: "グランスタ東京;地下1階",
    locality: "丸の内一丁目",
    district: "千代田区",
    city: "東京都",
    state: null,
  });
  eq(
    [tokyo.city, tokyo.state, tokyo.street, tokyo.housenumber],
    ["千代田区", "東京都", "丸の内一丁目", null],
    tokyo,
  );
  const skytree = localize({
    street: "1",
    housenumber: "2",
    locality: "押上一丁目",
    district: "墨田区",
    city: "墨田区",
    state: "東京都",
  });
  eq([skytree.city, skytree.street, skytree.housenumber], ["墨田区", "押上一丁目", "1-2"], skytree);
  const hachioji = localize({
    street: "野猿街道",
    locality: "旭町",
    district: "八王子市",
    city: "東京都",
  });
  eq([hachioji.city, hachioji.street, hachioji.housenumber], ["八王子市", "旭町", null], hachioji);
  const yokohama = localize({
    street: "横浜西口",
    locality: "相鉄ジョイナス地下街",
    district: "西区",
    city: "横浜市",
    state: "神奈川県",
  });
  eq([yokohama.city], ["横浜市"], yokohama);
  const sapporo = localize({ name: "北6条西3丁目", district: "北区", city: "札幌市", state: "北海道" });
  eq(["street" in sapporo, sapporo.city], [false, "札幌市"], sapporo);
  const towns: Towns = new Map([
    [
      "東京都",
      [
        ["東和四丁目", "足立区", 35.773291, 139.841935],
        ["谷中一丁目", "葛飾区", 35.77, 139.85],
        ["丸の内一丁目", "千代田区", 35.6813, 139.7671],
      ],
    ],
  ]);
  const towa = localize(
    { street: "蒲原通り", locality: "東和四丁目", district: "東和", city: "東京都" },
    [139.839, 35.776],
    towns,
  );
  eq([towa.city, towa.state, towa.street], ["足立区", "東京都", "東和四丁目"], towa);
  // No 町丁目 of that name: nearest within NEAREST_ONLY_KM, and nothing from across the prefecture.
  const near = localize({ locality: "どこか", district: "東和", city: "東京都" }, [139.842, 35.7735], towns);
  eq([near.city], ["足立区"], near);
  const far = localize({ locality: "どこか", district: "奥多摩", city: "東京都" }, [139.1, 35.8], towns);
  eq([far.city], ["奥多摩"], far);
  // Abroad: the nearest GeoNames town, never a Japanese one.
  const cells: Cells = new Map([
    ["37,-123", [["San Francisco", "California", "United States", "US", 37.77493, -122.41942]]],
    [
      "37,-122",
      [
        ["Oakland", "California", "United States", "US", 37.80437, -122.2708],
        ["Palo Alto", "California", "United States", "US", 37.44188, -122.14302],
      ],
    ],
  ]);
  const sf = placeFeatures(37.779, -122.419, cells).features[0].properties;
  eq(
    [sf.city, sf.state, sf.country, sf.countrycode],
    ["San Francisco", "California", "United States", "US"],
    sf,
  );
  eq([placeFeatures(37.43, -122.16, cells).features[0].properties.city], ["Palo Alto"], "palo alto");
  eq([placeFeatures(0.0, 0.0, cells).features], [[]], "nowhere");
  eq(
    [inJapan(35.68, 139.77), inJapan(26.21, 127.68), inJapan(37.77, -122.42)],
    [true, true, false],
    "in_japan",
  );
  console.log("ok");
}

if (import.meta.main) {
  if (process.argv.length === 3 && process.argv[2] === "--selftest") {
    selftest();
  } else {
    for (const [k, v] of await loadTowns()) TOWNS.set(k, v);
    const total = [...TOWNS.values()].reduce((n, v) => n + v.length, 0);
    console.error(`isj: ${total} 町丁目 in ${TOWNS.size} prefectures`);
    try {
      for (const [k, v] of await loadPlaces()) PLACES.set(k, v);
    } catch (e) {
      // abroad stays unnamed until a restart
      console.error(`geonames: ${e instanceof PyError || e instanceof HttpError ? e.repr : String(e)}`);
    }
    const places = [...PLACES.values()].reduce((n, v) => n + v.length, 0);
    console.error(`geonames: ${places} towns`);
    serve(PORT);
  }
}
