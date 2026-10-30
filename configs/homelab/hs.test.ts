// Regression tests for hs.ts. podman, systemctl, journalctl, restic, ytdl-sub and jq are stubs
// alone on PATH. The loopback service URLs hs hard-codes are reached through HTTP_PROXY pointing
// at a fake proxy in this process, so no request leaves the test even when those ports are taken.
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { hostname, tmpdir } from "node:os";
import { join } from "node:path";

const SCRIPT = join(import.meta.dir, "hs.ts");
// hs exports this file's variables over the test's; tests that depend on credentials are skipped
// on a machine that has it.
const HAS_SECRETS = existsSync("/var/lib/secrets/homelab-cli.env");

const STUB_JS = `
import { appendFileSync, existsSync, readFileSync, writeFileSync, writeSync } from "node:fs";
const [name, ...args] = process.argv.slice(2);
const env = process.env;
appendFileSync(env.STUB_LOG, JSON.stringify([name, ...args]) + "\\n");
const fix = (f) => env.FIX + "/" + f;
const lines = (f) => (existsSync(fix(f)) ? readFileSync(fix(f), "utf8").split("\\n") : []);
const out = (s) => writeSync(1, s);
const rc = Number(env.STUB_RC || "0");
const a = args.join(" ");
if (name === "podman") {
  if (args[0] === "container" && args[1] === "exists") {
    if (existsSync(fix("wake-after"))) {
      const n = Number(existsSync(fix("wake-count")) ? readFileSync(fix("wake-count"), "utf8") : "0") + 1;
      writeFileSync(fix("wake-count"), String(n));
      if (n > Number(readFileSync(fix("wake-after"), "utf8"))) process.exit(0);
    }
    process.exit(lines("containers").includes(args[2]) ? 0 : 1);
  }
  if (a === "ps --format json") { out(readFileSync(fix("ps.json"), "utf8")); process.exit(0); }
  if (args[0] === "ps") { out("NAMES\\tSTATUS\\tIMAGE\\n"); process.exit(0); }
  if (args[0] === "inspect") { out(readFileSync(fix("inspect.json"), "utf8")); process.exit(0); }
  if (args[0] === "exec") { out("podman-exec " + a + "\\n"); process.exit(rc); }
}
if (name === "systemctl") {
  const m = /^cat podman-(.*)\\.service$/.exec(a);
  if (m) process.exit(lines("units").includes(m[1]) ? 0 : 1);
  if (a === "--no-pager --failed") { out("fixture failed list\\n"); process.exit(0); }
  out("systemctl-called " + a + "\\n");
  process.exit(rc);
}
if (name === "journalctl") { out("journalctl-called " + a + "\\n"); process.exit(rc); }
if (name === "restic") {
  out("restic-called " + a + " repo=" + env.RESTIC_REPOSITORY + " pw=" + env.RESTIC_PASSWORD_FILE + " rc=" + env.RCLONE_CONFIG + "\\n");
  process.exit(rc);
}
if (name === "ytdl-sub") { out("ytdl-called " + a + "\\n"); process.exit(rc); }
if (name === "jq") { out("jq " + a + "\\n" + (await Bun.stdin.text())); process.exit(0); }
writeSync(2, "stub " + name + ": unhandled " + a + "\\n");
process.exit(99);
`;

const STUBS = ["podman", "systemctl", "journalctl", "restic", "ytdl-sub", "jq"];

const USAGE = `Usage:
  hs list
  hs status [app]
  hs unit status|logs|restart UNIT [ARG...]
  hs logs APP [journalctl options]
  hs restart APP
  hs exec APP COMMAND [ARG...]
  hs api APP METHOD PATH [JSON]
  hs openapi APP
  hs forms list|get|create|update|delete|responses|export [ARG...]
  hs share create SHARE_ID EXPIRATION FILE [FILE...]
  hs ytdl check|run|inspect [MATCH]
  hs navidrome COMMAND [ARG...]
  hs archivebox COMMAND [ARG...]
  hs forgejo COMMAND [ARG...]
  hs paperless COMMAND [ARG...]
  hs backup snapshots|check|run|restore-drill

API tokens are read from /var/lib/secrets/homelab-cli.env as
HS_<APP>_TOKEN (hyphens become underscores). Most use Bearer auth;
Miniflux, Paperless, and Bambuddy get their native header automatically.
Pingvin Share can instead use HS_PINGVIN_SHARE_EMAIL and
HS_PINGVIN_SHARE_PASSWORD; hs obtains a short-lived cookie automatically.
Formera uses HS_FORMERA_EMAIL and HS_FORMERA_PASSWORD to obtain a short-lived
bearer token; the token itself is never stored.
`;

type Hit = {
  method: string;
  url: string;
  auth: string | null;
  cookie: string | null;
  ct: string | null;
  accept: string | null;
  apiKey: string | null;
  authToken: string | null;
  body: string;
};
type Result = { code: number; stdout: string; stderr: string; calls: string[][]; http: Hit[]; cwd: string };

let root = "";
let stubDir = "";
let emptyDir = "";
let stubLog = "";
let proxy: ReturnType<typeof Bun.serve>;
let deadPort = 0;
let proxyVerified = false;
const seen: Hit[] = [];
let run = 0;

const UUID_RE = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/g;
const json = (v: unknown, status = 200): Response => new Response(JSON.stringify(v), { status, headers: { "content-type": "application/json" } });

function upstream(u: URL, body: string): Response {
  const p = u.pathname;
  if (u.host === "127.0.0.1:8100") {
    if (p === "/api/auth/login") return JSON.parse(body).password === "good" ? json({ token: "FT" }) : json({ error: "no" }, 401);
    if (p === "/swagger/doc.json") return json({ swagger: "2.0" });
    if (p.includes("missing")) return json({ error: "nf" }, 404);
    if (p.endsWith("/export/csv")) return new Response("a,b\n1,2\n");
    return json({ ok: true });
  }
  if (u.host === "127.0.0.1:8094") {
    if (p === "/api/auth/signIn") return JSON.parse(body).password === "good" ? json({ accessToken: "PT" }) : json({ e: 1 }, 401);
    if (p === "/api/configs") return json([{ key: "other", value: "x" }, { key: "share.chunkSize", value: "7" }]);
    return json({ ok: true });
  }
  if (u.host === "127.0.0.1:8091") {
    if (p === "/text") return new Response("plain text body\n");
    if (p === "/null") return new Response("null");
    if (p === "/err") return json({ e: 1 }, 500);
    return json({ openapi: "3.0.0", n: 1.5 });
  }
  return json({ host: u.host, path: p });
}

function fixtures(fix: string): void {
  mkdirSync(fix);
  writeFileSync(join(fix, "containers"), "paperless\nnavidrome\n");
  writeFileSync(join(fix, "units"), "paperless\nromm-db\nsleepy\n");
  writeFileSync(
    join(fix, "ps.json"),
    '[{"Names":["zeta"],"Image":"docker.io/z:1","Status":"Up 2 hours"},{"Names":["alpha"],"Image":"docker.io/a:1","Status":"Up 5 minutes (healthy)"}]\n',
  );
  writeFileSync(
    join(fix, "inspect.json"),
    '[{"Name":"paperless","ImageName":"ghcr.io/paperless:2","State":{"Status":"running","Health":{"Status":"healthy"}},"RestartCount":3,"Mounts":[{"Source":"/a","Destination":"/b","RW":true}]}]\n',
  );
}

async function hs(
  args: string[],
  opts: { env?: Record<string, string>; path?: string; proxyPort?: number; pre?: (fix: string, cwd: string) => void } = {},
): Promise<Result> {
  if (!proxyVerified) throw new Error("HTTP_PROXY is not honoured by bun fetch; refusing to run hs");
  const dir = join(root, `run-${++run}`);
  const fix = join(dir, "fix");
  const cwd = join(dir, "cwd");
  mkdirSync(cwd, { recursive: true });
  fixtures(fix);
  opts.pre?.(fix, cwd);
  seen.length = 0;
  writeFileSync(stubLog, "");
  const proxyUrl = `http://127.0.0.1:${opts.proxyPort ?? proxy.port}`;
  const p = Bun.spawn([process.execPath, "--no-env-file", SCRIPT, ...args], {
    cwd,
    env: { PATH: opts.path ?? stubDir, HOME: root, FIX: fix, STUB_LOG: stubLog, HTTP_PROXY: proxyUrl, http_proxy: proxyUrl, ...opts.env },
    stdin: "ignore",
    stdout: "pipe",
    stderr: "pipe",
  });
  const [stdout, stderr, code] = await Promise.all([new Response(p.stdout).text(), new Response(p.stderr).text(), p.exited]);
  const calls = readFileSync(stubLog, "utf8")
    .split("\n")
    .filter(Boolean)
    .map((l) => JSON.parse(l) as string[]);
  return { code, stdout, stderr, calls, http: [...seen], cwd };
}

const GOOD = { HS_FORMERA_EMAIL: "a@b", HS_FORMERA_PASSWORD: "good", HS_PINGVIN_SHARE_EMAIL: "p@q", HS_PINGVIN_SHARE_PASSWORD: "good" };
const hit = (method: string, url: string, extra: Partial<Hit> = {}): Hit => ({
  method,
  url,
  auth: null,
  cookie: null,
  ct: null,
  accept: "*/*",
  apiKey: null,
  authToken: null,
  body: "",
  ...extra,
});

beforeAll(async () => {
  root = mkdtempSync(join(tmpdir(), "hs-test-"));
  stubDir = join(root, "bin");
  emptyDir = join(root, "empty-bin");
  stubLog = join(root, "stub.log");
  mkdirSync(stubDir);
  mkdirSync(emptyDir);
  writeFileSync(join(root, "stub.mjs"), STUB_JS);
  for (const name of STUBS) {
    const p = join(stubDir, name);
    writeFileSync(p, `#!/bin/sh\nexec '${process.execPath}' --no-env-file '${join(root, "stub.mjs")}' ${name} "$@"\n`);
    chmodSync(p, 0o755);
  }
  proxy = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    async fetch(req) {
      const u = new URL(req.url);
      const body = await req.text();
      const h = (k: string): string | null => req.headers.get(k);
      seen.push({
        method: req.method,
        url: `${u.origin}${u.pathname}${u.search}`.replace(UUID_RE, "<uuid>"),
        auth: h("authorization"),
        cookie: h("cookie"),
        ct: h("content-type"),
        accept: h("accept"),
        apiKey: h("x-api-key"),
        authToken: h("x-auth-token"),
        body,
      });
      return upstream(u, body);
    },
  });
  const dead = Bun.serve({ hostname: "127.0.0.1", port: 0, fetch: () => new Response() });
  deadPort = dead.port ?? 0;
  dead.stop(true);
  // A child bun with the same proxy variables must reach the fake proxy for a loopback URL
  // (port 9 is harmless even if the proxy were bypassed).
  const proxyUrl = `http://127.0.0.1:${proxy.port}`;
  const probe = Bun.spawn([process.execPath, "--no-env-file", "-e", 'await fetch("http://127.0.0.1:9/probe").catch(() => {});'], {
    cwd: root,
    env: { PATH: stubDir, HOME: root, HTTP_PROXY: proxyUrl, http_proxy: proxyUrl },
    stdout: "ignore",
    stderr: "ignore",
  });
  await probe.exited;
  proxyVerified = seen.some((s) => s.url === "http://127.0.0.1:9/probe");
});

afterAll(() => {
  proxy?.stop(true);
  if (root) rmSync(root, { recursive: true, force: true });
});

test("the fake proxy intercepts loopback fetches", () => {
  expect(proxyVerified).toBe(true);
});

describe("usage", () => {
  for (const args of [[], ["help"], ["-h"], ["--help"]]) {
    test(`hs ${args.join(" ")} prints usage to stdout`, async () => {
      const r = await hs(args);
      expect(r).toMatchObject({ code: 0, stdout: USAGE, stderr: "", calls: [] });
    });
  }

  test("an unknown command exits 2 with usage on stderr", async () => {
    const r = await hs(["frobnicate"]);
    expect(r).toMatchObject({ code: 2, stdout: "", stderr: `unknown command: frobnicate\n${USAGE}`, calls: [] });
  });

  for (const args of [["unit", "status"], ["unit", "frob", "x"], ["exec", "paperless"], ["api", "romm", "GET"], ["ytdl", "frob"], ["backup", "frob"], ["navidrome"], ["share", "create", "id", "never"]]) {
    test(`hs ${args.join(" ")} is a usage error`, async () => {
      const r = await hs(args);
      expect(r.code).toBe(2);
      expect(r.stderr).toBe(USAGE);
      expect(r.http).toEqual([]);
    });
  }
});

describe("containers and units", () => {
  test("list sorts podman's array by name and colours it with jq", async () => {
    const r = await hs(["list"]);
    expect(r.code).toBe(0);
    expect(r.calls).toEqual([
      ["podman", "ps", "--format", "json"],
      ["jq", "-C", "."],
    ]);
    expect(r.stdout).toBe(
      'jq -C .\n{"name":["alpha"],"image":"docker.io/a:1","status":"Up 5 minutes (healthy)"}\n{"name":["zeta"],"image":"docker.io/z:1","status":"Up 2 hours"}',
    );
  });

  test("status of a running container summarises podman inspect", async () => {
    const r = await hs(["status", "paperless"]);
    expect(r.code).toBe(0);
    expect(r.calls).toEqual([
      ["podman", "container", "exists", "paperless"],
      ["podman", "inspect", "paperless"],
      ["jq", "-C", "."],
    ]);
    expect(r.stdout).toBe(
      'jq -C .\n{"name":"paperless","image":"ghcr.io/paperless:2","state":"running","health":"healthy","restarts":3,"mounts":[{"Source":"/a","Destination":"/b","RW":true}]}',
    );
  });

  test("status of a socket-activated container that is asleep", async () => {
    const r = await hs(["status", "sleepy"]);
    expect(r.code).toBe(0);
    expect(r.calls).toEqual([
      ["podman", "container", "exists", "sleepy"],
      ["systemctl", "cat", "podman-sleepy.service"],
      ["jq", "-C", "."],
    ]);
    expect(r.stdout).toBe('jq -C .\n{"name":"sleepy","state":"sleeping"}');
  });

  test("status of an unknown container exits 2", async () => {
    const r = await hs(["status", "nope"]);
    expect(r).toMatchObject({ code: 2, stdout: "", stderr: "unknown container: nope\n" });
  });

  test("status without an app shows failed units and the podman table", async () => {
    const r = await hs(["status"]);
    expect(r.code).toBe(0);
    expect(r.calls).toEqual([
      ["systemctl", "--no-pager", "--failed"],
      ["podman", "ps", "--format", "table {{.Names}}\\t{{.Status}}\\t{{.Image}}"],
    ]);
    expect(r.stdout).toBe("fixture failed list\nNAMES\tSTATUS\tIMAGE\n");
  });

  test("unit status/logs/restart pass arguments through", async () => {
    expect((await hs(["unit", "status", "blocky", "-n", "5"])).calls).toEqual([["systemctl", "status", "--no-pager", "blocky", "-n", "5"]]);
    expect((await hs(["unit", "logs", "restic-backups-homeserver", "-n", "100"])).calls).toEqual([
      ["journalctl", "-u", "restic-backups-homeserver", "--no-pager", "-n", "100"],
    ]);
    // restart ignores extra arguments
    const r = await hs(["unit", "restart", "syncthing", "extra"]);
    expect(r.calls).toEqual([["systemctl", "restart", "syncthing"]]);
    expect(r.stdout).toBe("systemctl-called restart syncthing\n");
  });

  test("the child's exit status becomes hs's", async () => {
    const r = await hs(["unit", "restart", "syncthing"], { env: { STUB_RC: "3" } });
    expect(r.code).toBe(3);
  });

  test("logs of a known app; unknown app is a usage error", async () => {
    const r = await hs(["logs", "paperless", "-f", "--since", "today"]);
    expect(r.code).toBe(0);
    expect(r.calls).toEqual([
      ["systemctl", "cat", "podman-paperless.service"],
      ["journalctl", "-u", "podman-paperless.service", "--no-pager", "-f", "--since", "today"],
    ]);
    const u = await hs(["logs", "nope"]);
    expect(u.code).toBe(2);
    expect(u.calls).toEqual([["systemctl", "cat", "podman-nope.service"]]);
  });

  test("restart of a running container", async () => {
    const r = await hs(["restart", "paperless"]);
    expect(r.code).toBe(0);
    expect(r.calls).toEqual([
      ["podman", "container", "exists", "paperless"],
      ["systemctl", "restart", "podman-paperless.service"],
    ]);
    expect(r.http).toEqual([]);
  });

  test("restart of an unknown container exits 2 without touching systemd", async () => {
    const r = await hs(["restart", "nope"]);
    expect(r).toMatchObject({ code: 2, stderr: "unknown container: nope\n", calls: [["podman", "container", "exists", "nope"]] });
  });

  test("restart wakes a socket-activated container through its HTTP group first", async () => {
    const r = await hs(["restart", "romm-db"], { pre: (fix) => writeFileSync(join(fix, "wake-after"), "1") });
    expect(r.code).toBe(0);
    expect(r.http).toEqual([hit("GET", "http://127.0.0.1:8091/")]);
    expect(r.calls).toEqual([
      ["podman", "container", "exists", "romm-db"],
      ["podman", "container", "exists", "romm-db"],
      ["systemctl", "restart", "podman-romm-db.service"],
    ]);
  });

  test("exec runs podman exec -it and returns its status", async () => {
    const r = await hs(["exec", "paperless", "sh", "-c", "echo hi"]);
    expect(r.calls.at(-1)).toEqual(["podman", "exec", "-it", "paperless", "sh", "-c", "echo hi"]);
    expect(r.stdout).toBe("podman-exec exec -it paperless sh -c echo hi\n");
    expect((await hs(["exec", "paperless", "false"], { env: { STUB_RC: "5" } })).code).toBe(5);
  });

  test("app shortcuts run their CLI inside the container", async () => {
    expect((await hs(["navidrome", "scan", "--full"])).calls).toEqual([["podman", "exec", "-it", "navidrome", "/app/navidrome", "scan", "--full"]]);
    expect((await hs(["archivebox", "add", "https://x"])).calls).toEqual([["podman", "exec", "-it", "archivebox", "archivebox", "add", "https://x"]]);
    expect((await hs(["forgejo", "admin", "user", "list"])).calls).toEqual([
      ["podman", "exec", "-u", "git", "-it", "forgejo", "forgejo", "admin", "user", "list"],
    ]);
    expect((await hs(["paperless", "document_index", "reindex"])).calls).toEqual([
      ["podman", "exec", "-it", "paperless", "python3", "manage.py", "document_index", "reindex"],
    ]);
  });

  test("ytdl subcommands", async () => {
    const config = "/etc/homelab/ytdl-sub-config.yaml";
    const subs = "/etc/homelab/ytdl-sub-subscriptions.yaml";
    expect((await hs(["ytdl", "check"])).calls).toEqual([["ytdl-sub", "--dry-run", "--config", config, "sub", subs]]);
    expect((await hs(["ytdl", "run", "Some Channel"])).calls).toEqual([["ytdl-sub", "--config", config, "--match", "Some Channel", "sub", subs]]);
    expect((await hs(["ytdl", "inspect"])).calls).toEqual([["ytdl-sub", "--config", config, "inspect", subs]]);
  });

  test("backup subcommands", async () => {
    const snap = await hs(["backup", "snapshots"]);
    const host = hostname().split(".")[0];
    expect(snap.calls).toEqual([["restic", "snapshots", "--host", host]]);
    expect(snap.stdout).toBe(
      `restic-called snapshots --host ${host} repo=rclone:google-drive:restic-backup pw=/var/lib/secrets/restic.password rc=/var/lib/secrets/rclone.conf\n`,
    );
    const check = await hs(["backup", "check"], { env: { STUB_RC: "4" } });
    expect(check.code).toBe(4);
    expect(check.calls).toEqual([["restic", "check"]]);
    expect((await hs(["backup", "run"])).calls).toEqual([["systemctl", "start", "restic-backups-homeserver.service"]]);
    expect((await hs(["backup", "restore-drill"])).calls).toEqual([["systemctl", "start", "restore-drill.service"]]);
  });

  test("a missing command exits 127", async () => {
    const r = await hs(["restart", "paperless"], { path: emptyDir });
    expect(r).toMatchObject({ code: 127, stdout: "", stderr: "hs: podman: command not found\n" });
  });
});

describe.skipIf(HAS_SECRETS)("HTTP", () => {
  test("api with a JSON answer colours it with jq", async () => {
    const r = await hs(["api", "romm", "GET", "/openapi.json"]);
    expect(r.code).toBe(0);
    expect(r.http).toEqual([hit("GET", "http://127.0.0.1:8091/openapi.json", { accept: "application/json" })]);
    expect(r.calls).toEqual([["jq", "-C", "."]]);
    expect(r.stdout).toBe('jq -C .\n{"openapi":"3.0.0","n":1.5}');
  });

  test("api with a non-JSON or null answer prints it raw", async () => {
    const t = await hs(["api", "romm", "GET", "/text"]);
    expect(t).toMatchObject({ code: 0, stdout: "plain text body\n", calls: [] });
    const n = await hs(["api", "romm", "GET", "/null"]);
    expect(n).toMatchObject({ code: 0, stdout: "null", calls: [] });
  });

  test("an HTTP error is curl's exit 22", async () => {
    const r = await hs(["api", "romm", "GET", "/err"]);
    expect(r).toMatchObject({ code: 22, stdout: "", stderr: "curl: (22) The requested URL returned error: 500\n" });
  });

  test("a refused connection is curl's exit 7", async () => {
    const r = await hs(["api", "dawarich", "GET", "/x"], { proxyPort: deadPort });
    expect(r.code).toBe(7);
    expect(r.stderr).toMatch(/^curl: \(7\) Failed to connect to 127\.0\.0\.1:3005 after \d+ ms: Could not connect to server\n$/);
  });

  test("each app gets its native auth header", async () => {
    const cases: [string, Record<string, string>, Partial<Hit>][] = [
      ["paperless", { HS_PAPERLESS_TOKEN: "ptok" }, { auth: "Token ptok" }],
      ["bambuddy", { HS_BAMBUDDY_TOKEN: "btok" }, { apiKey: "btok" }],
      ["syncthing", { HS_SYNCTHING_TOKEN: "stok" }, { apiKey: "stok" }],
      ["miniflux", { HS_MINIFLUX_TOKEN: "mtok" }, { authToken: "mtok" }],
      ["rallly", { HS_RALLLY_TOKEN: "rtok" }, { auth: "Bearer rtok" }],
      ["rallly", { HS_RALLLY_COOKIE: "session=abc" }, { cookie: "session=abc" }],
      ["pingvin-share", { ...GOOD, HS_PINGVIN_SHARE_TOKEN: "x" }, { auth: "Bearer x" }],
    ];
    for (const [app, env, extra] of cases) {
      const r = await hs(["api", app, "GET", "/api/x"], { env });
      expect(r.code).toBe(0);
      expect(r.http).toHaveLength(1);
      expect(r.http[0]).toMatchObject({ method: "GET", accept: "application/json", ...extra });
    }
  });

  test("api with a JSON body sends it verbatim", async () => {
    const r = await hs(["api", "romm", "POST", "/x", '{"a": 1, "b": [true]}']);
    expect(r.code).toBe(0);
    expect(r.http).toEqual([
      hit("POST", "http://127.0.0.1:8091/x", { accept: "application/json", ct: "application/json", body: '{"a": 1, "b": [true]}' }),
    ]);
  });

  test("an invalid or null body is refused before any request", async () => {
    const b = await hs(["api", "romm", "POST", "/x", "{bad"]);
    expect(b).toMatchObject({ code: 5, http: [] });
    const n = await hs(["api", "romm", "POST", "/x", "null"]);
    expect(n).toMatchObject({ code: 1, stdout: "", http: [] });
  });

  test("an unknown app exits 2 without a request", async () => {
    const r = await hs(["api", "nosuch", "GET", "/x"]);
    expect(r).toMatchObject({ code: 2, stderr: "no API URL registered for: nosuch\n", http: [] });
  });

  test("Pingvin Share signs in with email and password and sends the cookie", async () => {
    const r = await hs(["api", "pingvin-share", "GET", "/api/shares"], { env: GOOD });
    expect(r.code).toBe(0);
    expect(r.http).toEqual([
      hit("POST", "http://127.0.0.1:8094/api/auth/signIn", { ct: "application/json", body: '{"email":"p@q","password":"good"}' }),
      hit("GET", "http://127.0.0.1:8094/api/shares", { accept: "application/json", cookie: "access_token=PT" }),
    ]);
  });

  test("a failed Pingvin Share sign-in stops with 22", async () => {
    const r = await hs(["api", "pingvin-share", "GET", "/api/shares"], { env: { HS_PINGVIN_SHARE_EMAIL: "p", HS_PINGVIN_SHARE_PASSWORD: "bad" } });
    expect(r).toMatchObject({ code: 22, stderr: "curl: (22) The requested URL returned error: 401\n" });
    expect(r.http.map((h) => h.url)).toEqual(["http://127.0.0.1:8094/api/auth/signIn"]);
  });

  test("Formera logs in for a bearer token", async () => {
    const r = await hs(["forms", "list"], { env: GOOD });
    expect(r.code).toBe(0);
    expect(r.http).toEqual([
      hit("POST", "http://127.0.0.1:8100/api/auth/login", { ct: "application/json", body: '{"email":"a@b","password":"good"}' }),
      hit("GET", "http://127.0.0.1:8100/api/forms?page_size=100", { accept: "application/json", auth: "Bearer FT" }),
    ]);
  });

  test("Formera without credentials exits 1; a failed login surfaces as 4", async () => {
    const none = await hs(["api", "formera", "GET", "/api/forms"]);
    expect(none).toMatchObject({ code: 1, stderr: "HS_FORMERA_EMAIL and HS_FORMERA_PASSWORD are required\n", http: [] });
    const bad = await hs(["forms", "export", "F1", "csv"], { env: { HS_FORMERA_EMAIL: "a", HS_FORMERA_PASSWORD: "bad" } });
    expect(bad).toMatchObject({ code: 4, stderr: "curl: (22) The requested URL returned error: 401\n" });
    expect(bad.http).toHaveLength(1);
  });

  test("forms create compacts the JSON file; a broken file is 5", async () => {
    const r = await hs(["forms", "create", "form.json"], {
      env: GOOD,
      pre: (_fix, cwd) => writeFileSync(join(cwd, "form.json"), '{"title": "Form", "n": 1, "fields": []}\n'),
    });
    expect(r.code).toBe(0);
    expect(r.http[1]).toEqual(
      hit("POST", "http://127.0.0.1:8100/api/forms", { accept: "application/json", auth: "Bearer FT", ct: "application/json", body: '{"title":"Form","n":1,"fields":[]}' }),
    );
    const bad = await hs(["forms", "create", "bad.json"], { env: GOOD, pre: (_fix, cwd) => writeFileSync(join(cwd, "bad.json"), "{bad") });
    expect(bad.code).toBe(5);
    expect(bad.http).toEqual([]);
    const missing = await hs(["forms", "create", "nope.json"], { env: GOOD });
    expect(missing).toMatchObject({ code: 2, stderr: "not a JSON file: nope.json\n", http: [] });
  });

  test("forms export to stdout and to a file", async () => {
    const out = await hs(["forms", "export", "F1", "csv"], { env: GOOD });
    expect(out).toMatchObject({ code: 0, stdout: "a,b\n1,2\n" });
    expect(out.http[1]).toEqual(hit("GET", "http://127.0.0.1:8100/api/forms/F1/export/csv", { auth: "Bearer FT" }));
    const file = await hs(["forms", "export", "F1", "csv", "out.csv"], { env: GOOD });
    expect(file).toMatchObject({ code: 0, stdout: "out.csv\n" });
    expect(readFileSync(join(file.cwd, "out.csv"), "utf8")).toBe("a,b\n1,2\n");
    const fmt = await hs(["forms", "export", "F1", "xml"], { env: GOOD });
    expect(fmt).toMatchObject({ code: 2, stderr: "export format must be csv or json\n", http: [] });
    const missing = await hs(["forms", "export", "missing", "csv"], { env: GOOD });
    expect(missing).toMatchObject({ code: 22, stderr: "curl: (22) The requested URL returned error: 404\n" });
  });

  test("openapi locations", async () => {
    const f = await hs(["openapi", "formera"]);
    expect(f.http).toEqual([hit("GET", "http://127.0.0.1:8100/swagger/doc.json")]);
    expect(f.stdout).toBe('jq -C .\n{"swagger":"2.0"}');
    expect((await hs(["openapi", "rallly"])).http.map((h) => h.url)).toEqual(["http://127.0.0.1:8089/api/private/openapi"]);
    expect((await hs(["openapi", "bambuddy"])).http.map((h) => h.url)).toEqual(["http://127.0.0.1:8010/openapi.json"]);
    const bogus = await hs(["openapi", "bogus"]);
    expect(bogus).toMatchObject({ code: 2, stderr: "OpenAPI location is not registered for: bogus\n", http: [] });
  });

  test("share create uploads files in chunks and completes the share", async () => {
    const id = "my-share_with_a_rather_long_identifier_x";
    const r = await hs(["share", "create", id, "never", "f1.bin", "empty.bin", "f3 name&x.bin"], {
      env: GOOD,
      pre: (_fix, cwd) => {
        writeFileSync(join(cwd, "f1.bin"), "f1-content-15b\n");
        writeFileSync(join(cwd, "empty.bin"), "");
        writeFileSync(join(cwd, "f3 name&x.bin"), "abcdefg");
      },
    });
    expect(r.code).toBe(0);
    expect(r.stdout).toBe(
      `f1.bin: 1/3 chunks\nf1.bin: 2/3 chunks\nf1.bin: 3/3 chunks\nf3 name&x.bin: 1/1 chunks\nhttps://send.gapul.net/share/${id}\n`,
    );
    const base = `http://127.0.0.1:8094/api/shares/${id}`;
    const chunk = (q: string, body: string): Hit => hit("POST", `${base}/files?id=<uuid>&${q}`, { cookie: "access_token=PT", ct: "application/octet-stream", body });
    expect(r.http).toEqual([
      hit("POST", "http://127.0.0.1:8094/api/auth/signIn", { ct: "application/json", body: '{"email":"p@q","password":"good"}' }),
      hit("GET", "http://127.0.0.1:8094/api/configs"),
      hit("POST", "http://127.0.0.1:8094/api/shares", {
        cookie: "access_token=PT",
        ct: "application/json",
        body: `{"id":"${id}","name":"my-share_with_a_rather_long_id","expiration":"never","description":"","recipients":[],"security":{},"size":22}`,
      }),
      chunk("name=f1.bin&chunkIndex=0&totalChunks=3", "f1-cont"),
      chunk("name=f1.bin&chunkIndex=1&totalChunks=3", "ent-15b"),
      chunk("name=f1.bin&chunkIndex=2&totalChunks=3", "\n"),
      chunk("name=f3%20name%26x.bin&chunkIndex=0&totalChunks=1", "abcdefg"),
      hit("POST", `${base}/complete`, { cookie: "access_token=PT" }),
    ]);
  });

  test("share create validates the ID and files before signing in", async () => {
    const id = await hs(["share", "create", "bad id!", "never", "x"], { env: GOOD });
    expect(id).toMatchObject({ code: 2, stderr: "share ID must be 3-50 letters, digits, underscores, or hyphens\n", http: [] });
    const file = await hs(["share", "create", "myshare", "never", "/nonexistent"], { env: GOOD });
    expect(file).toMatchObject({ code: 2, stderr: "not a file: /nonexistent\n", http: [] });
  });
});
