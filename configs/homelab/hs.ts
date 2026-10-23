#!/usr/bin/env bun
// hs: the single entry point for operating the homeserver from the CLI.
//
// Ported from configs/homelab/hs.sh. Subcommands, usage text, output and exit codes are kept;
// HTTP goes through fetch instead of curl, and failures are reported with curl's exit codes
// (7 connect, 22 HTTP error, 28 timeout) so scripts calling hs see the same statuses. jq stays,
// but only to colour JSON for display (`jq -C`), which is what hs has always printed.
import { readFileSync, statSync, writeFileSync, writeSync } from "node:fs";
import { hostname } from "node:os";

const out = (line: string): void => void writeSync(1, `${line}\n`);
const err = (line: string): void => void writeSync(2, `${line}\n`);

function die(message: string, code: number): never {
  err(message);
  process.exit(code);
}

// ── secrets ──────────────────────────────────────────────────────────
// The shell version sourced this file with `set -a`. It only ever holds KEY=value lines
// (optionally quoted), so read those and export them to child processes as well.
const secrets = "/var/lib/secrets/homelab-cli.env";
function loadSecrets(path: string): void {
  let text: string;
  try {
    text = readFileSync(path, "utf8");
  } catch {
    return;
  }
  for (const raw of text.split("\n")) {
    const line = raw.trim();
    if (line === "" || line.startsWith("#")) continue;
    const m = /^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$/.exec(line);
    if (!m) continue;
    let value = m[2];
    if (value.length >= 2 && value.startsWith("'") && value.endsWith("'")) {
      value = value.slice(1, -1);
    } else if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      value = value.slice(1, -1).replace(/\\(["\\$`])/g, "$1");
    }
    process.env[m[1]] = value;
  }
}
loadSecrets(secrets);

const usageText = `Usage:
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
bearer token; the token itself is never stored.`;

const usage = (fd: 1 | 2 = 1): void => void writeSync(fd, `${usageText}\n`);
function usageExit(): never {
  usage(2);
  process.exit(2);
}

// ── subprocesses ─────────────────────────────────────────────────────
function missing(cmd: string): never {
  die(`hs: ${cmd}: command not found`, 127);
}

function run(
  cmd: string[],
  opts: { stdin?: Uint8Array | string; stdout?: "pipe" | "inherit" | "ignore"; stderr?: "inherit" | "ignore"; env?: Record<string, string> } = {},
): { code: number; stdout: Buffer } {
  if (!Bun.which(cmd[0])) missing(cmd[0]);
  const p = Bun.spawnSync(cmd, {
    stdin: opts.stdin === undefined ? "inherit" : typeof opts.stdin === "string" ? Buffer.from(opts.stdin) : opts.stdin,
    stdout: opts.stdout ?? "inherit",
    stderr: opts.stderr ?? "inherit",
    env: opts.env ? { ...process.env, ...opts.env } : undefined,
  });
  const code = p.exitCode ?? 128 + (p.signalCode ? (signalNumbers[p.signalCode] ?? 0) : 0);
  return { code, stdout: p.stdout ?? Buffer.alloc(0) };
}

const signalNumbers: Record<string, number> = { SIGHUP: 1, SIGINT: 2, SIGQUIT: 3, SIGKILL: 9, SIGTERM: 15, SIGPIPE: 13 };

// Stands in for the shell's `exec`: the child owns the terminal, and hs leaves with its status.
// Ctrl-C reaches the child through the process group, so hs itself ignores it and waits.
async function execInto(cmd: string[], env?: Record<string, string>): Promise<never> {
  if (!Bun.which(cmd[0])) missing(cmd[0]);
  const child = Bun.spawn(cmd, {
    stdin: "inherit",
    stdout: "inherit",
    stderr: "inherit",
    env: env ? { ...process.env, ...env } : undefined,
  });
  process.on("SIGINT", () => {});
  process.on("SIGQUIT", () => {});
  for (const sig of ["SIGTERM", "SIGHUP"] as const) process.on(sig, () => child.kill(sig));
  const code = await child.exited;
  process.exit(child.signalCode ? 128 + (signalNumbers[child.signalCode] ?? 0) : code);
}

// Statuses other than 0 end hs with the same code, like `set -e` did.
function check(code: number): void {
  if (code !== 0) process.exit(code);
}

// `jq -C .` over a JSON text (or stream). jq is kept for its colour output only.
function showJson(text: Uint8Array | string): void {
  check(run(["jq", "-C", "."], { stdin: text }).code);
}

const podmanExists = (app: string): boolean => run(["podman", "container", "exists", app]).code === 0;
const knownUnit = (app: string): boolean =>
  run(["systemctl", "cat", `podman-${app}.service`], { stdout: "ignore", stderr: "ignore" }).code === 0;

// ── HTTP ─────────────────────────────────────────────────────────────
const baseUrls: Record<string, string> = {
  archivebox: "http://127.0.0.1:8000",
  bambuddy: "http://127.0.0.1:8010",
  calnode: "http://127.0.0.1:8086",
  dawarich: "http://127.0.0.1:3005",
  filestash: "http://127.0.0.1:8099",
  formera: "http://127.0.0.1:8100",
  forgejo: "http://127.0.0.1:3003",
  gameyfin: "http://127.0.0.1:8092",
  homeassistant: "http://127.0.0.1:8123",
  jellyfin: "http://127.0.0.1:8096",
  miniflux: "http://127.0.0.1:8081",
  navidrome: "http://127.0.0.1:4533",
  ntfy: "http://127.0.0.1:8082",
  paperless: "http://127.0.0.1:8097",
  "pingvin-share": "http://127.0.0.1:8094",
  radicale: "http://127.0.0.1:5232",
  rallly: "http://127.0.0.1:8089",
  readeck: "http://127.0.0.1:8087",
  romm: "http://127.0.0.1:8091",
  rsshub: "http://127.0.0.1:1200",
  spliit: "http://127.0.0.1:8090",
  syncthing: "http://127.0.0.1:8384",
  vaultwarden: "http://127.0.0.1:8080",
};

function baseUrl(app: string): string {
  const url = baseUrls[app];
  if (url === undefined) die(`no API URL registered for: ${app}`, 2);
  return url;
}

interface HttpOpts {
  method?: string;
  headers?: Record<string, string>;
  body?: string | Blob;
  // curl -f: an HTTP status >= 400 is a failure (exit 22) rather than a body to print.
  fail?: boolean;
  timeoutMs?: number;
}

type HttpResult = { ok: true; res: Response; bytes: Uint8Array } | { ok: false; code: number; message: string };

// fetch with curl's failure vocabulary. The caller decides whether a failure ends hs.
async function http(url: string, opts: HttpOpts = {}): Promise<HttpResult> {
  const timeoutMs = opts.timeoutMs;
  const started = Date.now();
  let res: Response;
  try {
    res = await fetch(url, {
      method: opts.method ?? (opts.body !== undefined ? "POST" : "GET"),
      headers: opts.headers,
      body: opts.body,
      signal: timeoutMs ? AbortSignal.timeout(timeoutMs) : undefined,
    });
  } catch (e) {
    const name = e instanceof Error ? e.name : "";
    if (name === "TimeoutError" || name === "AbortError") {
      return { ok: false, code: 28, message: `curl: (28) Operation timed out after ${timeoutMs} milliseconds with 0 bytes received` };
    }
    const u = new URL(url);
    return {
      ok: false,
      code: 7,
      message: `curl: (7) Failed to connect to ${u.hostname}:${u.port || "80"} after ${Date.now() - started} ms: Could not connect to server`,
    };
  }
  if (opts.fail && res.status >= 400) {
    await res.body?.cancel();
    return { ok: false, code: 22, message: `curl: (22) The requested URL returned error: ${res.status}` };
  }
  return { ok: true, res, bytes: new Uint8Array(await res.arrayBuffer()) };
}

// Fails like `curl -fsS`: print curl's message and exit with `code` (curl's own unless the
// shell version piped curl into jq, where pipefail reported jq's status instead).
async function mustHttp(url: string, opts: HttpOpts, code?: number): Promise<Uint8Array> {
  const r = await http(url, { ...opts, fail: true });
  if (!r.ok) die(r.message, code ?? r.code);
  return r.bytes;
}

const decode = (b: Uint8Array): string => new TextDecoder().decode(b);

// writeSync may write only part of a large buffer to a pipe.
function writeAll(fd: number, bytes: Uint8Array): void {
  for (let off = 0; off < bytes.length; ) off += writeSync(fd, bytes, off);
}

function parseJson(text: string): { ok: true; value: unknown } | { ok: false } {
  try {
    return { ok: true, value: JSON.parse(text) };
  } catch {
    return { ok: false };
  }
}

// What `jq -r` prints for a value.
const jqRaw = (v: unknown): string => (typeof v === "string" ? v : JSON.stringify(v ?? null));

// `jq -er .field`: no output and exit 4 for empty input, exit 1 for null/false.
function jqField(bytes: Uint8Array, field: string): string {
  const text = decode(bytes);
  if (text.trim() === "") process.exit(4);
  const parsed = parseJson(text);
  if (!parsed.ok) die("jq: parse error: response is not JSON", 5);
  const value =
    parsed.value !== null && typeof parsed.value === "object" ? (parsed.value as Record<string, unknown>)[field] : undefined;
  if (value === undefined || value === null || value === false) {
    out(jqRaw(value));
    process.exit(1);
  }
  return jqRaw(value);
}

// HS_<APP>_TOKEN / HS_<APP>_COOKIE, hyphens becoming underscores.
const appEnv = (app: string, suffix: string): string =>
  process.env[`HS_${app.toUpperCase()}_${suffix}`.replaceAll("-", "_")] ?? "";

async function formeraToken(): Promise<string> {
  const email = process.env.HS_FORMERA_EMAIL ?? "";
  const password = process.env.HS_FORMERA_PASSWORD ?? "";
  if (email === "" || password === "") die("HS_FORMERA_EMAIL and HS_FORMERA_PASSWORD are required", 1);
  // `curl | jq -er .token` under pipefail: a failed login surfaces as jq's 4.
  const bytes = await mustHttp(
    `${baseUrl("formera")}/api/auth/login`,
    { headers: { "Content-Type": "application/json" }, body: JSON.stringify({ email, password }) },
    4,
  );
  return jqField(bytes, "token");
}

async function pingvinCookie(): Promise<string> {
  const email = process.env.HS_PINGVIN_SHARE_EMAIL ?? "";
  const password = process.env.HS_PINGVIN_SHARE_PASSWORD ?? "";
  if (email === "" || password === "") die("HS_PINGVIN_SHARE_EMAIL and HS_PINGVIN_SHARE_PASSWORD are required", 1);
  const bytes = await mustHttp(`${baseUrl("pingvin-share")}/api/auth/signIn`, {
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  return `access_token=${jqField(bytes, "accessToken")}`;
}

async function api(app: string, method: string, path: string, body = ""): Promise<void> {
  const token = appEnv(app, "TOKEN");
  const headers = new Headers({ Accept: "application/json" });
  if (token !== "") {
    switch (app) {
      case "bambuddy":
      case "syncthing":
        headers.append("X-API-Key", token);
        break;
      case "miniflux":
        headers.append("X-Auth-Token", token);
        break;
      case "paperless":
        headers.append("Authorization", `Token ${token}`);
        break;
      default:
        headers.append("Authorization", `Bearer ${token}`);
    }
  }
  const cookie = appEnv(app, "COOKIE");
  if (cookie !== "") headers.append("Cookie", cookie);

  if (
    app === "pingvin-share" &&
    token === "" &&
    cookie === "" &&
    (process.env.HS_PINGVIN_SHARE_EMAIL ?? "") !== "" &&
    (process.env.HS_PINGVIN_SHARE_PASSWORD ?? "") !== ""
  ) {
    headers.append("Cookie", await pingvinCookie());
  }
  if (app === "formera" && token === "") {
    headers.append("Authorization", `Bearer ${await formeraToken()}`);
  }
  let payload: string | undefined;
  if (body !== "") {
    // `jq -e .` used to vet the body: invalid JSON is 5, null/false is 1.
    const parsed = parseJson(body);
    if (!parsed.ok) die("jq: parse error: request body is not valid JSON", 5);
    if (parsed.value === null || parsed.value === false) process.exit(1);
    headers.append("Content-Type", "application/json");
    payload = body;
  }
  const url = baseUrl(app) + path;
  const r = await http(url, { method, headers: Object.fromEntries(headers), body: payload, fail: true });
  if (!r.ok) die(r.message, r.code);
  const parsed = parseJson(decode(r.bytes));
  if (parsed.ok && parsed.value !== null && parsed.value !== false) {
    showJson(r.bytes);
  } else {
    writeAll(1, r.bytes);
  }
}

// ── containers ───────────────────────────────────────────────────────
// Socket-activated containers do not exist while asleep. Wake the owning
// HTTP group, then wait for the ordinary podman operation to become possible.
const wakeApps: Record<string, string> = {
  "formera-backend": "formera",
  gameyfin: "gameyfin",
  jellyfin: "jellyfin",
  "pingvin-share": "pingvin-share",
  rallly: "rallly",
  romm: "romm",
  spliit: "spliit",
  "rallly-db": "rallly",
  "romm-db": "romm",
  "spliit-db": "spliit",
};

async function needApp(app: string | undefined): Promise<string> {
  if (!app) usageExit();
  if (podmanExists(app)) return app;
  let wakeUrl: string;
  if (app === "formera-frontend") wakeUrl = "http://127.0.0.1:8101";
  else if (wakeApps[app] !== undefined) wakeUrl = baseUrl(wakeApps[app]);
  else die(`unknown container: ${app}`, 2);
  // curl -sS without -f: any HTTP answer is fine, only transport errors are printed.
  const r = await http(`${wakeUrl}/`, { timeoutMs: 150_000 });
  if (!r.ok) err(r.message);
  for (let i = 0; i < 120; i++) {
    if (podmanExists(app)) return app;
    await Bun.sleep(1000);
  }
  die(`container did not wake: ${app}`, 1);
}

// jq's ordering for the arrays podman reports in .Names.
function compareNames(a: unknown, b: unknown): number {
  const xs = Array.isArray(a) ? a.map(String) : [String(a ?? "")];
  const ys = Array.isArray(b) ? b.map(String) : [String(b ?? "")];
  for (let i = 0; i < Math.min(xs.length, ys.length); i++) {
    if (xs[i] !== ys[i]) return xs[i] < ys[i] ? -1 : 1;
  }
  return xs.length - ys.length;
}

// ── Pingvin Share ────────────────────────────────────────────────────
// jq's @uri: everything but A-Za-z0-9 and -_.~ is percent-encoded, byte by byte.
function uriEncode(value: string): string {
  let s = "";
  for (const byte of Buffer.from(value, "utf8")) {
    const c = String.fromCharCode(byte);
    s += /[A-Za-z0-9\-_.~]/.test(c) ? c : `%${byte.toString(16).toUpperCase().padStart(2, "0")}`;
  }
  return s;
}

const isFile = (path: string): boolean => {
  try {
    return statSync(path).isFile();
  } catch {
    return false;
  }
};

async function pingvinShareCreate(shareId: string, expiration: string, files: string[]): Promise<void> {
  if (files.length === 0) usageExit();
  if (!/^[a-zA-Z0-9_-]{3,50}$/.test(shareId)) {
    die("share ID must be 3-50 letters, digits, underscores, or hyphens", 2);
  }
  let totalSize = 0;
  for (const file of files) {
    if (!isFile(file)) die(`not a file: ${file}`, 2);
    totalSize += statSync(file).size;
  }

  const cookie = await pingvinCookie();
  const base = baseUrl("pingvin-share");
  // `curl | jq -er '... | tonumber'`: under pipefail a failed request surfaces as jq's 4.
  const configs = parseJson(decode(await mustHttp(`${base}/api/configs`, {}, 4)));
  if (!configs.ok) die("jq: parse error: /api/configs is not JSON", 5);
  const entry = (Array.isArray(configs.value) ? configs.value : []).find(
    (c): c is { value: unknown } => typeof c === "object" && c !== null && (c as { key?: unknown }).key === "share.chunkSize",
  );
  if (entry === undefined) process.exit(4);
  const chunkSize = Number(entry.value);
  if (!Number.isFinite(chunkSize) || chunkSize <= 0) die(`jq: error: ${JSON.stringify(entry.value)} cannot be parsed as a number`, 5);

  await mustHttp(`${base}/api/shares`, {
    headers: { Cookie: cookie, "Content-Type": "application/json" },
    body: JSON.stringify({
      id: shareId,
      name: shareId.slice(0, 30),
      expiration,
      description: "",
      recipients: [],
      security: {},
      size: totalSize,
    }),
  });

  for (const file of files) {
    const name = file.split("/").filter(Boolean).pop() ?? file;
    const encodedName = uriEncode(name);
    const fileId = crypto.randomUUID();
    const blob = Bun.file(file);
    const size = statSync(file).size;
    const total = Math.ceil(size / chunkSize);
    for (let index = 0; index < total; index++) {
      await mustHttp(
        `${base}/api/shares/${shareId}/files?id=${fileId}&name=${encodedName}&chunkIndex=${index}&totalChunks=${total}`,
        {
          headers: { Cookie: cookie, "Content-Type": "application/octet-stream" },
          body: blob.slice(index * chunkSize, (index + 1) * chunkSize),
        },
      );
      out(`${name}: ${index + 1}/${total} chunks`);
    }
  }
  await mustHttp(`${base}/api/shares/${shareId}/complete`, { method: "POST", headers: { Cookie: cookie } });
  out(`https://send.gapul.net/share/${shareId}`);
}

// ── Formera ──────────────────────────────────────────────────────────
async function formeraExport(formId: string, format: string, output: string): Promise<void> {
  if (format !== "csv" && format !== "json") die("export format must be csv or json", 2);
  const token = await formeraToken();
  const bytes = await mustHttp(`${baseUrl("formera")}/api/forms/${formId}/export/${format}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (output === "-") {
    writeAll(1, bytes);
  } else {
    writeFileSync(output, bytes);
    out(output);
  }
}

// `jq -c . FILE`: the form definition, compacted. A file that is not JSON fails with jq's 5.
function compactJsonFile(file: string): string {
  const parsed = parseJson(readFileSync(file, "utf8"));
  if (!parsed.ok) die(`jq: error: ${file} is not valid JSON`, 5);
  return JSON.stringify(parsed.value);
}

async function formeraForms(args: string[]): Promise<void> {
  const [action = "", a1 = "", a2 = "", a3 = "-"] = args;
  switch (action) {
    case "list":
      return api("formera", "GET", "/api/forms?page_size=100");
    case "get":
      if (a1 === "") usageExit();
      return api("formera", "GET", `/api/forms/${a1}`);
    case "create":
      if (!isFile(a1)) die(`not a JSON file: ${a1}`, 2);
      return api("formera", "POST", "/api/forms", compactJsonFile(a1));
    case "update":
      if (a1 === "" || !isFile(a2)) usageExit();
      return api("formera", "PUT", `/api/forms/${a1}`, compactJsonFile(a2));
    case "delete":
      if (a1 === "") usageExit();
      return api("formera", "DELETE", `/api/forms/${a1}`);
    case "responses":
      if (a1 === "") usageExit();
      return api("formera", "GET", `/api/forms/${a1}/submissions?page_size=100`);
    case "export":
      if (a1 === "" || a2 === "") usageExit();
      return formeraExport(a1, a2, a3 === "" ? "-" : a3);
    default:
      usageExit();
  }
}

const resticEnv = {
  RESTIC_REPOSITORY: "rclone:google-drive:restic-backup",
  RESTIC_PASSWORD_FILE: "/var/lib/secrets/restic.password",
  RCLONE_CONFIG: "/var/lib/secrets/rclone.conf",
};

interface Inspect {
  Name?: unknown;
  ImageName?: unknown;
  State?: { Status?: unknown; Health?: { Status?: unknown } | null } | null;
  RestartCount?: unknown;
  Mounts?: unknown;
}

// ── main ─────────────────────────────────────────────────────────────
const [command = "", ...rest] = Bun.argv.slice(2);
switch (command) {
  case "list": {
    // The shell version slurped (`jq -s`) podman's output, which is already one array, and then
    // indexed that array as a container: `hs list` only ever printed a jq error. Flatten instead.
    const ps = run(["podman", "ps", "--format", "json"], { stdout: "pipe" });
    check(ps.code);
    const parsed = parseJson(decode(ps.stdout));
    if (!parsed.ok) die("jq: parse error: podman ps output is not JSON", 5);
    const containers = (Array.isArray(parsed.value) ? parsed.value : [parsed.value]) as Record<string, unknown>[];
    containers.sort((a, b) => compareNames(a.Names, b.Names));
    showJson(
      containers.map((c) => JSON.stringify({ name: c.Names ?? null, image: c.Image ?? null, status: c.Status ?? null })).join("\n"),
    );
    break;
  }
  case "status": {
    const app = rest[0] ?? "";
    if (app !== "") {
      if (podmanExists(app)) {
        const inspect = run(["podman", "inspect", app], { stdout: "pipe" });
        check(inspect.code);
        const parsed = parseJson(decode(inspect.stdout));
        if (!parsed.ok) die("jq: parse error: podman inspect output is not JSON", 5);
        const c = ((parsed.value as unknown[])[0] ?? {}) as Inspect;
        showJson(
          JSON.stringify({
            name: c.Name ?? null,
            image: c.ImageName ?? null,
            state: c.State?.Status ?? null,
            health: c.State?.Health?.Status ?? null,
            restarts: c.RestartCount ?? null,
            mounts: c.Mounts ?? null,
          }),
        );
      } else if (knownUnit(app)) {
        showJson(JSON.stringify({ name: app, state: "sleeping" }));
      } else {
        die(`unknown container: ${app}`, 2);
      }
    } else {
      check(run(["systemctl", "--no-pager", "--failed"]).code);
      check(run(["podman", "ps", "--format", "table {{.Names}}\\t{{.Status}}\\t{{.Image}}"]).code);
    }
    break;
  }
  case "unit": {
    const [action = "", unit = "", ...args] = rest;
    if (unit === "") usageExit();
    switch (action) {
      case "status":
        await execInto(["systemctl", "status", "--no-pager", unit, ...args]);
        break;
      case "logs":
        await execInto(["journalctl", "-u", unit, "--no-pager", ...args]);
        break;
      case "restart":
        await execInto(["systemctl", "restart", unit]);
        break;
      default:
        usageExit();
    }
    break;
  }
  case "logs": {
    const [app = "", ...args] = rest;
    if (app === "" || !knownUnit(app)) usageExit();
    await execInto(["journalctl", "-u", `podman-${app}.service`, "--no-pager", ...args]);
    break;
  }
  case "restart": {
    const app = await needApp(rest[0]);
    await execInto(["systemctl", "restart", `podman-${app}.service`]);
    break;
  }
  case "exec": {
    const app = await needApp(rest[0]);
    const args = rest.slice(1);
    if (args.length === 0) usageExit();
    await execInto(["podman", "exec", "-it", app, ...args]);
    break;
  }
  case "api":
    if (rest.length < 3) usageExit();
    await api(rest[0], rest[1], rest[2], rest[3] ?? "");
    break;
  case "openapi": {
    const app = rest[0] ?? "";
    switch (app) {
      case "bambuddy":
      case "romm":
        await api(app, "GET", "/openapi.json");
        break;
      case "formera":
        showJson(await mustHttp(`${baseUrl("formera")}/swagger/doc.json`, {}));
        break;
      // Rallly publishes the private schema even on self-hosted installations.
      // API-key creation is intentionally not bypassed here when upstream's
      // licence/feature gate disables it.
      case "rallly":
        await api(app, "GET", "/api/private/openapi");
        break;
      default:
        die(`OpenAPI location is not registered for: ${app}`, 2);
    }
    break;
  }
  case "forms":
    await formeraForms(rest);
    break;
  case "share": {
    const [action = "", ...args] = rest;
    if (action !== "create" || args.length < 3) usageExit();
    await pingvinShareCreate(args[0], args[1], args.slice(2));
    break;
  }
  case "ytdl": {
    const [action = "", match = ""] = rest;
    const config = "/etc/homelab/ytdl-sub-config.yaml";
    const subscriptions = "/etc/homelab/ytdl-sub-subscriptions.yaml";
    const matchArgs = match !== "" ? ["--match", match] : [];
    switch (action) {
      case "check":
        await execInto(["ytdl-sub", "--dry-run", "--config", config, ...matchArgs, "sub", subscriptions]);
        break;
      case "run":
        await execInto(["ytdl-sub", "--config", config, ...matchArgs, "sub", subscriptions]);
        break;
      case "inspect":
        await execInto(["ytdl-sub", "--config", config, ...matchArgs, "inspect", subscriptions]);
        break;
      default:
        usageExit();
    }
    break;
  }
  case "navidrome":
    if (rest.length === 0) usageExit();
    await execInto(["podman", "exec", "-it", "navidrome", "/app/navidrome", ...rest]);
    break;
  case "archivebox":
    if (rest.length === 0) usageExit();
    await execInto(["podman", "exec", "-it", "archivebox", "archivebox", ...rest]);
    break;
  case "forgejo":
    if (rest.length === 0) usageExit();
    await execInto(["podman", "exec", "-u", "git", "-it", "forgejo", "forgejo", ...rest]);
    break;
  case "paperless":
    if (rest.length === 0) usageExit();
    await execInto(["podman", "exec", "-it", "paperless", "python3", "manage.py", ...rest]);
    break;
  case "backup":
    switch (rest[0] ?? "") {
      case "snapshots":
        await execInto(["restic", "snapshots", "--host", hostname().split(".")[0]], resticEnv);
        break;
      case "check":
        await execInto(["restic", "check"], resticEnv);
        break;
      case "run":
        await execInto(["systemctl", "start", "restic-backups-homeserver.service"]);
        break;
      case "restore-drill":
        await execInto(["systemctl", "start", "restore-drill.service"]);
        break;
      default:
        usageExit();
    }
    break;
  case "help":
  case "-h":
  case "--help":
  case "":
    usage();
    break;
  default:
    err(`unknown command: ${command}`);
    usageExit();
}
