// Regression tests for the photon proxy against a fake photon on localhost.
//
// proxy.ts hardcodes its port (2323), its upstream (127.0.0.1:2322) and its data directories under
// HOME, so it runs with HOME set to a temp dir pre-filled with ISJ / GeoNames fixtures (nothing to
// download) and a --preload shim that moves Bun.serve to an ephemeral loopback port, rewrites the
// upstream URL to the fake and rejects every other fetch.
import { afterAll, beforeAll, beforeEach, expect, test } from "bun:test";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const SCRIPT = join(import.meta.dir, "proxy.ts");

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

// Shift_JIS encoder built by inverting the decoder (the MLIT CSVs are Shift_JIS).
function shiftJis(text: string): Uint8Array {
  const dec = new TextDecoder("shift_jis");
  const table = new Map<string, number[]>();
  for (let lead = 0x81; lead <= 0xfc; lead++) {
    if (lead > 0x9f && lead < 0xe0) continue;
    for (let trail = 0x40; trail <= 0xfc; trail++) {
      if (trail === 0x7f) continue;
      const ch = dec.decode(new Uint8Array([lead, trail]));
      if (ch.length === 1 && ch !== "�" && !table.has(ch)) table.set(ch, [lead, trail]);
    }
  }
  const out: number[] = [];
  for (const ch of text) {
    const cp = ch.codePointAt(0) ?? 0;
    if (cp < 0x80) out.push(cp);
    else {
      const bytes = table.get(ch);
      if (!bytes) throw new Error(`not in Shift_JIS: ${ch}`);
      out.push(...bytes);
    }
  }
  return Uint8Array.from(out);
}

// A one-member zip with the member stored (method 0).
function storedZip(name: string, data: Uint8Array): Uint8Array {
  const nameBytes = new TextEncoder().encode(name);
  const crc = Bun.hash.crc32(data);
  const local = new DataView(new ArrayBuffer(30));
  local.setUint32(0, 0x04034b50, true);
  local.setUint16(4, 20, true);
  local.setUint32(14, crc, true);
  local.setUint32(18, data.length, true);
  local.setUint32(22, data.length, true);
  local.setUint16(26, nameBytes.length, true);
  const central = new DataView(new ArrayBuffer(46));
  central.setUint32(0, 0x02014b50, true);
  central.setUint16(4, 20, true);
  central.setUint16(6, 20, true);
  central.setUint32(16, crc, true);
  central.setUint32(20, data.length, true);
  central.setUint32(24, data.length, true);
  central.setUint16(28, nameBytes.length, true);
  central.setUint32(42, 0, true);
  const cdOffset = 30 + nameBytes.length + data.length;
  const cdSize = 46 + nameBytes.length;
  const eocd = new DataView(new ArrayBuffer(22));
  eocd.setUint32(0, 0x06054b50, true);
  eocd.setUint16(8, 1, true);
  eocd.setUint16(10, 1, true);
  eocd.setUint32(12, cdSize, true);
  eocd.setUint32(16, cdOffset, true);
  const parts = [new Uint8Array(local.buffer), nameBytes, data, new Uint8Array(central.buffer), nameBytes, new Uint8Array(eocd.buffer)];
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const p of parts) {
    out.set(p, at);
    at += p.length;
  }
  return out;
}

const TOWA_UPSTREAM =
  '{"type":"FeatureCollection","features":[{"type":"Feature","geometry":{"type":"Point","coordinates":[139.839,35.776]},' +
  '"properties":{"osm_id":1,"countrycode":"JP","name":"蒲原通り","street":"蒲原通り","locality":"東和四丁目",' +
  '"district":"東和","city":"東京都","extent":[139.0,36.0,140.0,35.0]}}],"extra":"dropped"}';
const SKYTREE_UPSTREAM =
  '{"features":[{"type":"Feature","geometry":{"type":"Point","coordinates":[139.8107,35.7101]},' +
  '"properties":{"countrycode":"JP","street":"1","housenumber":"2","locality":"押上一丁目","district":"墨田区",' +
  '"city":"墨田区","state":"東京都"}},{"type":"Feature","geometry":{"type":"Point","coordinates":[139.8,35.7]},' +
  '"properties":{"countrycode":"KR","street":"9","locality":"x"}}]}';
const SEOUL_DEFAULT =
  '{"features":[{"type":"Feature","geometry":{"type":"Point","coordinates":[126.978,37.566]},"properties":{"countrycode":"KR","name":"서울"}}]}';
const SEOUL_EN = '{"features":[{"properties":{"countrycode":"KR","name":"Seoul"}}],"type":"FeatureCollection"}';

let root: string;
let photon: ReturnType<typeof Bun.serve>;
let proxy: ReturnType<typeof Bun.spawn>;
let base: string;
let upstream: string[] = [];
let stderrText: Promise<string>;

beforeAll(async () => {
  root = mkdtempSync(join(tmpdir(), "photon-proxy-test-"));
  const home = join(root, "home");
  const isj = join(home, ".local/share/photon/isj");
  mkdirSync(isj, { recursive: true });
  for (let n = 1; n < 48; n++) writeFileSync(join(isj, `${String(n).padStart(2, "0")}.csv`), "");
  writeFileSync(
    join(isj, "13.csv"),
    shiftJis(
      [
        '"都道府県コード","都道府県名","市区町村コード","市区町村名","大字町丁目コード","大字町丁目名","緯度","経度"',
        '"13","東京都","13121","足立区","131210","東和四丁目","35.773291","139.841935"',
        '"13","東京都","13101","千代田区","131010","丸の内一丁目","35.6813","139.7671"',
        "",
      ].join("\r\n"),
    ),
  );
  const geo = join(home, ".local/share/photon/geonames");
  mkdirSync(geo, { recursive: true });
  writeFileSync(join(geo, "countryInfo.txt"), "#ISO\tISO3\tISO-Numeric\tfips\tCountry\nUS\tUSA\t840\tUS\tUnited States\n");
  writeFileSync(join(geo, "admin1CodesASCII.txt"), "US.CA\tCalifornia\tCalifornia\t5332921\n");
  const city = (id: string, name: string, lat: string, lon: string, cc: string, a1: string) =>
    [id, name, name, "", lat, lon, "P", "PPL", cc, "", a1, "", "", "", "1000", "", "0", "UTC", "2020-01-01"].join("\t");
  writeFileSync(
    join(geo, "cities1000.zip"),
    storedZip(
      "cities1000.txt",
      new TextEncoder().encode(
        `${[
          city("5391959", "San Francisco", "37.77493", "-122.41942", "US", "CA"),
          city("5380748", "Palo Alto", "37.44188", "-122.14302", "US", "CA"),
        ].join("\n")}\n`,
      ),
    ),
  );

  photon = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    fetch(req) {
      const url = new URL(req.url);
      upstream.push(url.pathname + url.search);
      const q = url.searchParams;
      const json = (body: string) => new Response(body, { headers: { "Content-Type": "application/json" } });
      if (q.get("lat") === "35.776") return json(TOWA_UPSTREAM);
      if (q.get("lat") === "35.7101") return json(SKYTREE_UPSTREAM);
      if (q.get("q") === "Seoul") return json(q.get("lang") === "default" ? SEOUL_DEFAULT : SEOUL_EN);
      if (q.get("q") === "boom") return new Response("boom", { status: 500 });
      if (q.get("q") === "garbage") return json("not json");
      return json('{"features":[]}');
    },
  });

  const bunfig = join(root, "bunfig.toml");
  writeFileSync(bunfig, "");
  const shim = join(root, "shim.js");
  writeFileSync(shim, SHIM);
  const portFile = join(root, "port");
  proxy = Bun.spawn(
    [process.execPath, "--no-env-file", `--config=${bunfig}`, "--no-install", "--preload", shim, SCRIPT],
    {
      cwd: root,
      env: {
        HOME: home,
        PATH: process.env.PATH ?? "/usr/bin:/bin",
        TEST_PORT_FILE: portFile,
        TEST_FETCH_MAP: JSON.stringify({ "http://127.0.0.1:2322": `http://127.0.0.1:${photon.port}` }),
      },
      stdout: "pipe",
      stderr: "pipe",
    },
  );
  stderrText = new Response(proxy.stderr as ReadableStream).text();
  for (let i = 0; i < 100 && !existsSync(portFile); i++) await Bun.sleep(50);
  base = `http://127.0.0.1:${readFileSync(portFile, "utf8")}`;
});

afterAll(async () => {
  proxy?.kill();
  await proxy?.exited;
  photon?.stop(true);
  rmSync(root, { recursive: true, force: true });
});

beforeEach(() => {
  upstream = [];
});

test("loads the ISJ and GeoNames fixtures without downloading", async () => {
  // Probe once so the start-up lines have been written; they are checked after the proxy stops.
  const res = await fetch(`${base}/reverse?lat=-60&lon=0`);
  expect(res.status).toBe(200);
  expect(await res.text()).toBe('{"type": "FeatureCollection", "features": []}');
  expect(upstream).toEqual([]);
});

test("Japan: asks photon for lang=default and moves the ward and 町丁目 where Dawarich reads", async () => {
  const res = await fetch(`${base}/reverse?lat=35.776&lon=139.839&lang=en&limit=1`);
  expect(res.status).toBe(200);
  expect(res.headers.get("content-type")).toBe("application/json; charset=utf-8");
  expect(upstream).toEqual(["/reverse?lat=35.776&lon=139.839&lang=default&limit=1"]);
  // city was only the prefecture and the ward is nowhere in photon's answer: 足立区 comes from ISJ.
  expect(await res.text()).toBe(
    '{"type": "FeatureCollection", "features": [{"type": "Feature", "geometry": {"type": "Point", ' +
      '"coordinates": [139.839, 35.776]}, "properties": {"osm_id": 1, "countrycode": "JP", "name": "蒲原通り", ' +
      '"street": "東和四丁目", "locality": "東和四丁目", "district": "東和", "city": "足立区", ' +
      '"extent": [139.0, 36.0, 140.0, 35.0], "state": "東京都", "housenumber": null}}]}',
  );
});

test("Japan: a digits-only street becomes the 街区 part of the house number; non-JP features stay", async () => {
  const res = await fetch(`${base}/reverse?lat=35.7101&lon=139.8107`);
  expect(upstream).toEqual(["/reverse?lat=35.7101&lon=139.8107&lang=default"]);
  expect(await res.text()).toBe(
    '{"type": "FeatureCollection", "features": [{"type": "Feature", "geometry": {"type": "Point", ' +
      '"coordinates": [139.8107, 35.7101]}, "properties": {"countrycode": "JP", "street": "押上一丁目", ' +
      '"housenumber": "1-2", "locality": "押上一丁目", "district": "墨田区", "city": "墨田区", "state": "東京都"}}, ' +
      '{"type": "Feature", "geometry": {"type": "Point", "coordinates": [139.8, 35.7]}, ' +
      '"properties": {"countrycode": "KR", "street": "9", "locality": "x"}}]}',
  );
});

test("non-Japanese results are re-fetched with the original query and passed through byte for byte", async () => {
  const res = await fetch(`${base}/api?q=Seoul&lang=en`);
  expect(res.status).toBe(200);
  expect(upstream).toEqual(["/api?q=Seoul&lang=default", "/api?q=Seoul&lang=en"]);
  expect(await res.text()).toBe(SEOUL_EN);
});

test("abroad: answered from GeoNames without asking photon", async () => {
  const res = await fetch(`${base}/reverse?lat=37.43&lon=-122.16&lang=en`);
  expect(res.status).toBe(200);
  expect(upstream).toEqual([]);
  expect(await res.text()).toBe(
    '{"type": "FeatureCollection", "features": [{"type": "Feature", "geometry": {"type": "Point", ' +
      '"coordinates": [-122.14302, 37.44188]}, "properties": {"type": "city", "name": "Palo Alto", ' +
      '"city": "Palo Alto", "state": "California", "country": "United States", "countrycode": "US"}}]}',
  );
});

test("an upstream HTTP error is relayed with its status and body", async () => {
  const res = await fetch(`${base}/api?q=boom`);
  expect(res.status).toBe(500);
  expect(await res.text()).toBe("boom");
  expect(upstream).toEqual(["/api?q=boom&lang=default"]);
});

test("an unparsable upstream answer becomes a 502 with an ASCII JSON message", async () => {
  const res = await fetch(`${base}/api?q=garbage`);
  expect(res.status).toBe(502);
  const text = await res.text();
  expect(text).toMatch(/^\{"message": "[\x20-\x7e]*"\}$/);
  expect(JSON.parse(text).message.length).toBeGreaterThan(0);
});

test("non-GET methods get Python's 501 page", async () => {
  const res = await fetch(`${base}/reverse`, { method: "POST", body: "x" });
  expect(res.status).toBe(501);
  expect(res.headers.get("content-type")).toBe("text/html;charset=utf-8");
  expect(await res.text()).toContain("<p>Message: Unsupported method ('POST').</p>");
  expect(upstream).toEqual([]);
});

test("start-up log reports the fixture counts and no download attempts", async () => {
  proxy.kill();
  await proxy.exited;
  const err = await stderrText;
  expect(err).toContain("isj: 2 町丁目 in 1 prefectures");
  expect(err).toContain("geonames: 2 towns");
  expect(err).not.toContain("blocked by test shim");
  expect(err).not.toContain("upstream error for /api?q=Seoul");
});

test("--selftest passes (pure rewrite checks, no network)", async () => {
  const proc = Bun.spawn([process.execPath, "--no-env-file", `--config=${join(root, "bunfig.toml")}`, "--no-install", SCRIPT, "--selftest"], {
    cwd: root,
    env: { HOME: join(root, "selftest-home"), PATH: process.env.PATH ?? "/usr/bin:/bin" },
    stdout: "pipe",
    stderr: "pipe",
  });
  expect(await proc.exited).toBe(0);
  expect(await new Response(proc.stdout).text()).toBe("ok\n");
});
