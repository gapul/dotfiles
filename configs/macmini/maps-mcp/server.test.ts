// Regression tests for the maps MCP server (Streamable HTTP, POST /mcp).
//
// server.ts hardcodes its port (2324) and several upstream hosts, so it runs with a --preload
// shim that moves Bun.serve to an ephemeral loopback port and rejects every fetch except the
// localhost fake below (photon and SearXNG via PHOTON_URL / SEARXNG_URL, GSI via a URL rewrite).
// HOME is a temp dir; the Overture SQLite database is created there mid-run.
import { Database } from "bun:sqlite";
import { afterAll, beforeAll, beforeEach, expect, test } from "bun:test";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const SCRIPT = join(import.meta.dir, "server.ts");

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
const realServe = Bun.serve;
Bun.serve = (options) => {
  const s = realServe({ ...options, hostname: "127.0.0.1", port: 0 });
  require("node:fs").writeFileSync(process.env.TEST_PORT_FILE, String(s.port));
  return s;
};
`;

const INSTRUCTIONS =
  "Read-only map tools: geocoding, nearby places (Overture), Apple Maps search and " +
  "driving/walking/cycling routes, Japanese transit (Transitous), anonymous web " +
  "search, restaurant opening hours (Hot Pepper), weather. The user's own location history is in the separate dawarich MCP.";

type Json = any;

let root: string;
let home: string;
let fake: ReturnType<typeof Bun.serve>;
let server: ReturnType<typeof Bun.spawn>;
let base: string;
let upstream: string[] = [];
let stderrText: Promise<string>;

beforeAll(async () => {
  root = mkdtempSync(join(tmpdir(), "maps-mcp-test-"));
  home = join(root, "home");
  mkdirSync(home);
  fake = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    fetch(req) {
      const url = new URL(req.url);
      upstream.push(url.pathname + url.search);
      const q = url.searchParams;
      if (url.pathname === "/api") {
        if (q.get("q") === "down") return new Response("photon down", { status: 503 });
        return new Response(
          '{"features":[{"geometry":{"coordinates":[139.8,35.0]},"properties":{"name":"清澄庭園",' +
            '"osm_key":"leisure","osm_value":"park","state":"東京都","city":"江東区","street":""}}]}',
        );
      }
      if (url.pathname === "/reverse") {
        return Response.json({
          features: [
            {
              geometry: { coordinates: [139.8, 35.68] },
              properties: { name: "清澄庭園", state: "東京都", city: "江東区", street: "清澄三丁目", country: "日本", extra: 1 },
            },
          ],
        });
      }
      if (url.pathname === "/address-search/AddressSearch") {
        if (q.get("q") === "nogsi") return new Response("gsi down", { status: 500 });
        return Response.json(
          Array.from({ length: 4 }, (_, i) => ({
            geometry: { coordinates: [139.8, 35.68 + i / 100] },
            properties: { title: `東京都江東区清澄${i + 1}丁目` },
          })),
        );
      }
      if (url.pathname === "/search") {
        return Response.json({
          results: [
            { title: "T1", url: "https://a.example/", content: "x".repeat(305), engine: "google cse" },
            { title: "T2", url: "https://b.example/", content: "", engine: "google" },
          ],
          unresponsive_engines: [["google", "CAPTCHA"]],
        });
      }
      return new Response("not found", { status: 404 });
    },
  });

  const fakeOrigin = `http://127.0.0.1:${fake.port}`;
  const bunfig = join(root, "bunfig.toml");
  writeFileSync(bunfig, "");
  const shim = join(root, "shim.js");
  writeFileSync(shim, SHIM);
  const portFile = join(root, "port");
  server = Bun.spawn(
    [process.execPath, "--no-env-file", `--config=${bunfig}`, "--no-install", "--preload", shim, SCRIPT],
    {
      cwd: root,
      env: {
        HOME: home,
        PATH: process.env.PATH ?? "/usr/bin:/bin",
        PHOTON_URL: fakeOrigin,
        SEARXNG_URL: fakeOrigin,
        HOTPEPPER_KEY_PATH: join(root, "missing-hotpepper-key"),
        TEST_PORT_FILE: portFile,
        TEST_FETCH_MAP: JSON.stringify({
          [fakeOrigin]: fakeOrigin,
          "https://msearch.gsi.go.jp": fakeOrigin,
        }),
      },
      stdout: "pipe",
      stderr: "pipe",
    },
  );
  stderrText = new Response(server.stderr as ReadableStream).text();
  for (let i = 0; i < 100 && !existsSync(portFile); i++) await Bun.sleep(50);
  base = `http://127.0.0.1:${readFileSync(portFile, "utf8")}`;
});

afterAll(async () => {
  server?.kill();
  await server?.exited;
  fake?.stop(true);
  rmSync(root, { recursive: true, force: true });
});

beforeEach(() => {
  upstream = [];
});

async function post(body: unknown, path = "/mcp"): Promise<Response> {
  return fetch(`${base}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

async function rpc(method: string, params?: Json, id: Json = 1): Promise<Json> {
  const res = await post({ jsonrpc: "2.0", id, method, ...(params === undefined ? {} : { params }) });
  expect(res.status).toBe(200);
  expect(res.headers.get("content-type")).toBe("application/json");
  return res.json();
}

async function call(name: string, args?: Json): Promise<{ text: string; isError: boolean }> {
  const reply = await rpc("tools/call", { name, ...(args === undefined ? {} : { arguments: args }) });
  const result = reply.result;
  expect(result.content).toHaveLength(1);
  expect(result.content[0].type).toBe("text");
  return { text: result.content[0].text, isError: result.isError === true };
}

test("initialize echoes the protocol version and is serialised json.dumps-style", async () => {
  const res = await post({ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-03-26" } });
  expect(res.status).toBe(200);
  expect(await res.text()).toBe(
    '{"jsonrpc": "2.0", "id": 1, "result": {"protocolVersion": "2025-03-26", "capabilities": {"tools": {}}, ' +
      `"serverInfo": {"name": "maps", "version": "1.0"}, "instructions": "${INSTRUCTIONS}"}}`,
  );
});

test("initialize without params defaults to 2025-06-18; string ids are echoed", async () => {
  const reply = await rpc("initialize", undefined, "init-1");
  expect(reply.id).toBe("init-1");
  expect(reply.result.protocolVersion).toBe("2025-06-18");
});

test("ping returns an empty result", async () => {
  expect(await rpc("ping", undefined, 7)).toEqual({ jsonrpc: "2.0", id: 7, result: {} });
});

test("a notification gets 202 with no body", async () => {
  const res = await post({ jsonrpc: "2.0", method: "notifications/initialized" });
  expect(res.status).toBe(202);
  expect(await res.text()).toBe("");
});

test("tools/list: names, order, annotations and input schemas", async () => {
  const tools: Json[] = (await rpc("tools/list")).result.tools;
  expect(tools.map((t) => t.name)).toEqual([
    "geocode",
    "reverse_geocode",
    "nearby_places",
    "apple_search",
    "apple_route",
    "transit_route",
    "web_search",
    "hotpepper",
    "weather",
  ]);
  const N = { type: "number" };
  const S = { type: "string" };
  const I = { type: "integer" };
  const schemas = Object.fromEntries(tools.map((t) => [t.name, t.inputSchema]));
  expect(schemas).toEqual({
    geocode: { type: "object", properties: { query: S, near_lat: N, near_lon: N, limit: I }, required: ["query"] },
    reverse_geocode: { type: "object", properties: { lat: N, lon: N }, required: ["lat", "lon"] },
    nearby_places: {
      type: "object",
      properties: { lat: N, lon: N, radius_m: N, keyword: S, category: S, min_confidence: N, limit: I },
      required: ["lat", "lon"],
    },
    apple_search: { type: "object", properties: { query: S, near_lat: N, near_lon: N, limit: I }, required: ["query"] },
    apple_route: {
      type: "object",
      properties: {
        from_lat: N,
        from_lon: N,
        to_lat: N,
        to_lon: N,
        mode: { type: "string", enum: ["Automobile", "Walking", "Cycling"] },
        depart_at: S,
      },
      required: ["from_lat", "from_lon", "to_lat", "to_lon"],
    },
    transit_route: {
      type: "object",
      properties: {
        from_lat: N,
        from_lon: N,
        to_lat: N,
        to_lon: N,
        time_iso: S,
        arrive_by: { type: "boolean" },
        limit: I,
      },
      required: ["from_lat", "from_lon", "to_lat", "to_lon"],
    },
    web_search: { type: "object", properties: { query: S, engines: S, limit: I }, required: ["query"] },
    hotpepper: {
      type: "object",
      properties: { lat: N, lon: N, radius_m: N, keyword: S, limit: I },
      required: ["lat", "lon"],
    },
    weather: { type: "object", properties: { lat: N, lon: N, days: I }, required: ["lat", "lon"] },
  });
  for (const t of tools) {
    expect(t.annotations).toEqual({ readOnlyHint: true });
    expect(typeof t.description).toBe("string");
    expect(t.description.length).toBeGreaterThan(20);
  }
});

test("unknown method is a JSON-RPC -32601 error", async () => {
  expect(await rpc("resources/list", undefined, 3)).toEqual({
    jsonrpc: "2.0",
    id: 3,
    error: { code: -32601, message: "unknown method resources/list" },
  });
});

test("batch: replies in order, notifications dropped; all-notification batch is 202", async () => {
  const res = await post([
    { jsonrpc: "2.0", id: 1, method: "ping" },
    { jsonrpc: "2.0", method: "notifications/initialized" },
    { jsonrpc: "2.0", id: 2, method: "nope" },
  ]);
  expect(await res.text()).toBe(
    '[{"jsonrpc": "2.0", "id": 1, "result": {}}, ' +
      '{"jsonrpc": "2.0", "id": 2, "error": {"code": -32601, "message": "unknown method nope"}}]',
  );
  const empty = await post([{ jsonrpc: "2.0", method: "notifications/initialized" }]);
  expect(empty.status).toBe(202);
});

test("unknown tool and bad arguments answer 'bad request' with Python's wording", async () => {
  expect(await call("nope", {})).toEqual({ text: "bad request: KeyError('nope')", isError: true });
  expect(await call("reverse_geocode")).toEqual({
    text: "bad request: TypeError(\"reverse_geocode() missing 2 required positional arguments: 'lat' and 'lon'\")",
    isError: true,
  });
  expect(await call("transit_route", { from_lat: 1 })).toEqual({
    text:
      "bad request: TypeError(\"transit_route() missing 3 required positional arguments: " +
      "'from_lon', 'to_lat', and 'to_lon'\")",
    isError: true,
  });
  expect(await call("weather", { lat: 1 })).toEqual({
    text: "bad request: TypeError(\"weather() missing 1 required positional argument: 'lon'\")",
    isError: true,
  });
  expect(await call("geocode", { query: "x", foo: 1 })).toEqual({
    text: "bad request: TypeError(\"geocode() got an unexpected keyword argument 'foo'\")",
    isError: true,
  });
  expect(await call("geocode", [1])).toEqual({
    text: "bad request: TypeError('__main__.geocode() argument after ** must be a mapping, not list')",
    isError: true,
  });
  expect(await call("geocode", { query: "x", limit: "2" })).toEqual({
    text: "bad request: TypeError('slice indices must be integers or None or have an __index__ method')",
    isError: true,
  });
  expect(upstream).toEqual(["/api?q=x&limit=2", "/address-search/AddressSearch?q=x"]);
});

test("tools/call without params is a server error, not a JSON-RPC reply", async () => {
  const res = await post({ jsonrpc: "2.0", id: 1, method: "tools/call" });
  expect(res.status).toBe(500);
});

test("HTTP framing: GET 405, other methods 501, wrong path 404, bad JSON 400, trailing slash ok", async () => {
  expect((await fetch(`${base}/mcp`)).status).toBe(405);
  const put = await fetch(`${base}/mcp`, { method: "PUT", body: "{}" });
  expect(put.status).toBe(501);
  expect(put.headers.get("content-type")).toBe("text/html;charset=utf-8");
  expect(await put.text()).toContain("<p>Message: Unsupported method ('PUT').</p>");
  const wrong = await post({ jsonrpc: "2.0", id: 1, method: "ping" }, "/other");
  expect(wrong.status).toBe(404);
  expect(await wrong.text()).toContain("<p>Error code explanation: 404 - Nothing matches the given URI.</p>");
  const bad = await post("{not json");
  expect(bad.status).toBe(400);
  expect(await bad.text()).toContain("<p>Message: Bad Request.</p>");
  const slash = await post({ jsonrpc: "2.0", id: 9, method: "ping" }, "/mcp/");
  expect(await slash.json()).toEqual({ jsonrpc: "2.0", id: 9, result: {} });
});

test("geocode: photon + GSI requests and the merged, json.dumps-shaped answer", async () => {
  const r = await call("geocode", { query: "Kiyosumi Garden", near_lat: 35.68, near_lon: 139.8, limit: 2 });
  expect(r.isError).toBe(false);
  expect(upstream).toEqual([
    "/api?q=Kiyosumi+Garden&limit=2&lat=35.68&lon=139.8",
    "/address-search/AddressSearch?q=Kiyosumi+Garden",
  ]);
  expect(r.text).toBe(
    '{"photon": [{"name": "清澄庭園", "kind": "leisure=park", "address": "東京都 江東区", "lat": 35.0, "lon": 139.8}], ' +
      '"gsi": [{"title": "東京都江東区清澄1丁目", "lat": 35.68, "lon": 139.8}, ' +
      '{"title": "東京都江東区清澄2丁目", "lat": 35.69, "lon": 139.8}]}',
  );
});

test("geocode: a GSI failure is ignored, a photon failure is a tool error", async () => {
  const ok = await call("geocode", { query: "nogsi" });
  expect(ok.isError).toBe(false);
  expect(JSON.parse(ok.text).gsi).toEqual([]);
  const down = await call("geocode", { query: "down" });
  expect(down).toEqual({ text: "geocode failed: <HTTPError 503: 'Service Unavailable'> photon down", isError: true });
});

test("hosts other than the fakes are never reached (the shim's refusal surfaces as a tool error)", async () => {
  const r = await call("transit_route", { from_lat: 35.68, from_lon: 139.8, to_lat: 35.7, to_lon: 139.76 });
  expect(r.isError).toBe(true);
  expect(r.text).toStartWith("transit_route failed: URLError('blocked by test shim: https://api.transitous.org/api/v5/plan?");
  expect(r.text).toContain("fromPlace=35.68%2C139.8&toPlace=35.7%2C139.76");
});

test("web_search: SearXNG query and trimmed results", async () => {
  const r = await call("web_search", { query: "清澄 カフェ", limit: 1 });
  expect(upstream).toEqual([
    "/search?q=%E6%B8%85%E6%BE%84+%E3%82%AB%E3%83%95%E3%82%A7&format=json&engines=google%2Cgoogle+cse",
  ]);
  expect(JSON.parse(r.text)).toEqual({
    results: [{ title: "T1", url: "https://a.example/", snippet: "x".repeat(300), engine: "google cse" }],
    unresponsive: [["google", "CAPTCHA"]],
  });
});

test("hotpepper without a key file fails before any request", async () => {
  expect(await call("hotpepper", { lat: 35.68, lon: 139.8 })).toEqual({
    text: "hotpepper failed: FileNotFoundError(2, 'No such file or directory') ",
    isError: true,
  });
  expect(upstream).toEqual([]);
});

test("nearby_places without the Overture database", async () => {
  expect(await call("nearby_places", { lat: 35.68, lon: 139.8 })).toEqual({
    text: "nearby_places failed: RuntimeError('Overture database not built yet (~/.local/share/overture/build.sh)') ",
    isError: true,
  });
});

test("nearby_places and reverse_geocode read the Overture database", async () => {
  const dir = join(home, ".local/share/overture");
  mkdirSync(dir, { recursive: true });
  const db = new Database(join(dir, "japan.sqlite"));
  db.run(
    "CREATE TABLE places (name TEXT, category TEXT, taxonomy TEXT, confidence REAL, phone TEXT, " +
      "website TEXT, address TEXT, brand TEXT, lat REAL, lon REAL)",
  );
  db.run("CREATE TABLE addresses (pref TEXT, city TEXT, street TEXT, number TEXT, lat REAL, lon REAL)");
  const place = db.prepare("INSERT INTO places VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
  place.run("Cafe A", "coffee_shop", "food.cafe", 0.9, "03-0000-0000", null, "江東区1", "A", 35.681, 139.8);
  place.run("Cafe B", "coffee_shop", "food.cafe", 1, null, null, "江東区2", null, 35.6801, 139.8);
  place.run("Low", "coffee_shop", "food.cafe", 0.5, null, null, null, null, 35.6802, 139.8);
  place.run("Bar", "bar", "drink.bar", 0.95, null, null, null, null, 35.6803, 139.8);
  place.run("Far", "coffee_shop", "food.cafe", 0.99, null, null, null, null, 35.684, 139.8);
  db.run("INSERT INTO addresses VALUES ('東京都', '江東区', '清澄三丁目', '3', 35.6801, 139.8)");
  db.run("INSERT INTO addresses VALUES ('東京都', '江東区', '清澄三丁目', '9', 35.6804, 139.8)");
  db.close();

  const near = await call("nearby_places", { lat: 35.68, lon: 139.8, radius_m: 300, category: "coffee" });
  expect(near.isError).toBe(false);
  expect(near.text).toBe(
    '[{"name": "Cafe B", "category": "coffee_shop", "confidence": 1.0, "phone": null, "website": null, ' +
      '"address": "江東区2", "brand": null, "lat": 35.6801, "lon": 139.8, "distance_m": 11}, ' +
      '{"name": "Cafe A", "category": "coffee_shop", "confidence": 0.9, "phone": "03-0000-0000", "website": null, ' +
      '"address": "江東区1", "brand": "A", "lat": 35.681, "lon": 139.8, "distance_m": 111}]',
  );
  const limited = await call("nearby_places", { lat: 35.68, lon: 139.8, keyword: "Cafe", limit: 1 });
  expect(JSON.parse(limited.text).map((p: Json) => p.name)).toEqual(["Cafe B"]);

  const rev = await call("reverse_geocode", { lat: 35.68, lon: 139.8 });
  expect(upstream).toEqual(["/reverse?lat=35.68&lon=139.8"]);
  expect(rev.text).toBe(
    '{"photon": {"name": "清澄庭園", "state": "東京都", "city": "江東区", "street": "清澄三丁目", ' +
      '"housenumber": null, "postcode": null, "country": "日本"}, ' +
      '"nearest_address": {"address": "東京都江東区清澄三丁目3", "distance_m": 11}}',
  );
});

test("access log lines go to stderr", async () => {
  server.kill();
  await server.exited;
  const err = await stderrText;
  expect(err).toContain('127.0.0.1 "POST /mcp HTTP/1.1" 200 -');
  expect(err).toContain('127.0.0.1 "GET /mcp HTTP/1.1" 405 -');
  expect(err).toContain("127.0.0.1 code 404, message Not Found");
});
