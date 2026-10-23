// Regression tests for journal-alert.ts. journalctl and systemctl are stubs first (and alone) on
// PATH; ntfy is reached through HTTP_PROXY pointing at a fake proxy in this process, so the
// hard-coded http://127.0.0.1:8082/alerts never reaches a real ntfy.
import { afterAll, beforeAll, beforeEach, describe, expect, test } from "bun:test";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const SCRIPT = join(import.meta.dir, "journal-alert.ts");
const TOKEN_FILE = "/var/lib/secrets/ntfy-alerts.token";
const HAS_TOKEN = existsSync(TOKEN_FILE);

const STUB_JS = `
import { appendFileSync, readFileSync, writeSync } from "node:fs";
const [name, ...args] = process.argv.slice(2);
appendFileSync(process.env.STUB_LOG, JSON.stringify([name, ...args]) + "\\n");
const fix = (f) => { try { return readFileSync(process.env.FIX + "/" + f, "utf8"); } catch { return ""; } };
const line = args.join(" ");
if (name === "journalctl" && args[0] === "--since") { writeSync(1, fix("journal.txt")); process.exit(0); }
if (name === "systemctl" && line === "--failed --no-legend --plain --no-pager") { writeSync(1, fix("failed.txt")); process.exit(0); }
if (name === "systemctl" && line === "is-failed --quiet restic-backups-homeserver.service") process.exit(Number(fix("restic-rc").trim() || "1"));
writeSync(2, "stub " + name + ": unhandled " + line + "\\n");
process.exit(99);
`;

type Note = { method: string; url: string; title: string | null; priority: string | null; tags: string | null; auth: string | null; body: string };

let root = "";
let stubDir = "";
let fixDir = "";
let stateDir = "";
let stubLog = "";
let proxy: ReturnType<typeof Bun.serve>;
let proxyVerified = false;
const seen: Note[] = [];

function env(): Record<string, string> {
  const p = `http://127.0.0.1:${proxy.port}`;
  return {
    PATH: stubDir,
    HOME: root,
    STATE_DIRECTORY: stateDir,
    FIX: fixDir,
    STUB_LOG: stubLog,
    HTTP_PROXY: p,
    http_proxy: p,
  };
}

async function runAlert(args: string[] = []): Promise<{ code: number; stdout: string; stderr: string; notes: Note[]; calls: string[][] }> {
  if (!proxyVerified) throw new Error("HTTP_PROXY is not honoured by bun fetch; refusing to run journal-alert");
  seen.length = 0;
  writeFileSync(stubLog, "");
  const p = Bun.spawn([process.execPath, "--no-env-file", SCRIPT, ...args], {
    cwd: root,
    env: env(),
    stdin: "ignore",
    stdout: "pipe",
    stderr: "pipe",
  });
  const [stdout, stderr, code] = await Promise.all([new Response(p.stdout).text(), new Response(p.stderr).text(), p.exited]);
  const calls = readFileSync(stubLog, "utf8")
    .split("\n")
    .filter(Boolean)
    .map((l) => JSON.parse(l) as string[]);
  return { code, stdout, stderr, notes: [...seen], calls };
}

function fixture(journal: string[], failed: string[], resticRc: number): void {
  writeFileSync(join(fixDir, "journal.txt"), journal.map((l) => `${l}\n`).join(""));
  writeFileSync(join(fixDir, "failed.txt"), failed.map((l) => `${l}\n`).join(""));
  writeFileSync(join(fixDir, "restic-rc"), `${resticRc}\n`);
}

// State files as name -> fingerprint, after checking each has the "<epoch>\t<fp>\n" shape.
function state(): Record<string, string> {
  const out: Record<string, string> = {};
  for (const f of readdirSync(stateDir).sort()) {
    const m = /^(\d+)\t(.*)\n$/.exec(readFileSync(join(stateDir, f), "utf8"));
    if (!m) throw new Error(`bad state file ${f}`);
    out[f] = m[2];
  }
  return out;
}

function ageState(epoch: number): void {
  for (const f of readdirSync(stateDir)) {
    const p = join(stateDir, f);
    writeFileSync(p, readFileSync(p, "utf8").replace(/^\d+/, String(epoch)));
  }
}

const HEX64 = "a".repeat(64);
const TRANSIENT_UNIT = `${HEX64}-0123456789abcdef.service`;
const fail = (unit: string, minute: number): string => `Oct 23 10:${String(minute).padStart(2, "0")}:00 hs systemd[1]: ${unit}: Failed with result 'exit-code'.`;
const BIND_PREFIX = "Oct 23 10:42:00 hs podman[2]: Error: statfs /srv/x: no such file or directory ";
const BIND_LINE = BIND_PREFIX + "あ".repeat(80);

const JOURNAL = [
  ...[1, 2, 3, 4, 5, 6, 7].map((m) => fail("romm-db.service", m)),
  "Oct 23 10:00:00 hs romm-db[123]: mariadb abort tc.log corrupt",
  ...[11, 12, 13, 14, 15, 16].flatMap((m) => [fail("attic-db.service", m), fail("zz-db.service", m), fail(TRANSIENT_UNIT, m)]),
  "Oct 23 10:20:00 hs zz-db[9]: zz-db.service: FAILED WITH RESULT uppercase line",
  "Oct 23 10:21:00 hs zz-db[9]: zz-db.service sample line kept",
  ...[31, 32, 33, 34].map((m) => fail("few.service", m)),
  "Oct 23 10:40:00 hs hass[1]: Activating recovery mode because of config error",
  "Oct 23 10:41:00 hs hass[1]: Activating recovery mode again",
  BIND_LINE,
  "Oct 23 10:43:00 hs kernel: Out of memory: oom-kill:constraint=CONSTRAINT_NONE",
  "Oct 23 10:44:00 hs x[1]: Permission Denied (capitalised, must not match)",
];
const FAILED1 = ["nixos-upgrade.service loaded failed failed NixOS Upgrade", `${TRANSIENT_UNIT} loaded failed failed hc`];
const FAILED2 = ["foo@bar.service loaded failed failed x", "nixos-upgrade.service loaded failed failed NixOS Upgrade"];

// cut -c1-200 by bytes, backing off to a whole character: each あ is 3 bytes.
const BIND_SAMPLE = BIND_PREFIX + "あ".repeat(Math.floor((200 - Buffer.byteLength(BIND_PREFIX)) / 3));

const note = (title: string, body: string): Partial<Note> => ({ title, body, priority: "high", tags: "warning" });

function expectedFresh(window: string): Partial<Note>[] {
  return [
    note("Home Assistant が recovery mode に落ちた", `直近 ${window} で 2 件\nOct 23 10:41:00 hs hass[1]: Activating recovery mode again`),
    note("コンテナの bind mount 先が無い", `直近 ${window} で 1 件\n${BIND_SAMPLE}`),
    note("メモリ不足でプロセスが強制終了された", `直近 ${window} で 1 件\nOct 23 10:43:00 hs kernel: Out of memory: oom-kill:constraint=CONSTRAINT_NONE`),
    note("romm-db.service が失敗を繰り返している", `直近 ${window} で 7 回失敗。稼働中に見えても中身は起動できていない。\n`),
    note(
      "zz-db.service が失敗を繰り返している",
      `直近 ${window} で 6 回失敗。稼働中に見えても中身は起動できていない。\nOct 23 10:21:00 hs zz-db[9]: zz-db.service sample line kept`,
    ),
    note("attic-db.service が失敗を繰り返している", `直近 ${window} で 6 回失敗。稼働中に見えても中身は起動できていない。\n`),
  ];
}

const FRESH_STATE_LOOPS = {
  "loop-attic-db.service": "attic-db.service",
  "loop-romm-db.service": "romm-db.service",
  "loop-zz-db.service": "zz-db.service",
  "pattern-Activating-recovery-mode": "Activating recovery mode",
  "pattern-no-such-file-or-directory": "no such file or directory",
  "pattern-oom-kill": "oom-kill",
};

const STUB_CALLS = (since: string): string[][] => [
  ["journalctl", "--since", since, "--no-pager"],
  ["systemctl", "--failed", "--no-legend", "--plain", "--no-pager"],
  ["systemctl", "is-failed", "--quiet", "restic-backups-homeserver.service"],
];

beforeAll(async () => {
  root = mkdtempSync(join(tmpdir(), "journal-alert-test-"));
  stubDir = join(root, "bin");
  fixDir = join(root, "fix");
  stateDir = join(root, "state");
  stubLog = join(root, "stub.log");
  mkdirSync(stubDir);
  mkdirSync(fixDir);
  writeFileSync(join(root, "stub.mjs"), STUB_JS);
  for (const name of ["journalctl", "systemctl"]) {
    const p = join(stubDir, name);
    writeFileSync(p, `#!/bin/sh\nexec '${process.execPath}' --no-env-file '${join(root, "stub.mjs")}' ${name} "$@"\n`);
    chmodSync(p, 0o755);
  }
  proxy = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    async fetch(req) {
      const u = new URL(req.url);
      seen.push({
        method: req.method,
        url: `${u.origin}${u.pathname}`,
        title: u.searchParams.get("title"),
        priority: u.searchParams.get("priority"),
        tags: u.searchParams.get("tags"),
        auth: req.headers.get("authorization"),
        body: await req.text(),
      });
      return new Response("{}", { headers: { "content-type": "application/json" } });
    },
  });
  // A child bun with the same proxy variables must reach the fake proxy for a loopback URL
  // (port 9 is harmless even if the proxy were bypassed).
  const probe = Bun.spawn([process.execPath, "--no-env-file", "-e", 'await fetch("http://127.0.0.1:9/probe").catch(() => {});'], {
    cwd: root,
    env: env(),
    stdout: "ignore",
    stderr: "ignore",
  });
  await probe.exited;
  proxyVerified = seen.some((n) => n.url === "http://127.0.0.1:9/probe");
});

afterAll(() => {
  proxy?.stop(true);
  if (root) rmSync(root, { recursive: true, force: true });
});

test("the fake proxy intercepts loopback fetches", () => {
  expect(proxyVerified).toBe(true);
});

describe("dedupe sequence", () => {
  beforeAll(() => {
    rmSync(stateDir, { recursive: true, force: true });
  });

  test("fresh run notifies every signal once, in order, and records state", async () => {
    fixture(JOURNAL, FAILED1, 0);
    const r = await runAlert();
    expect(r.code).toBe(0);
    expect(r.stdout).toBe("");
    expect(r.calls).toEqual(STUB_CALLS("-15min"));
    expect(r.notes.map(({ method, url }) => `${method} ${url}`)).toEqual(Array(8).fill("POST http://127.0.0.1:8082/alerts"));
    expect(r.notes).toMatchObject([
      ...expectedFresh("15min"),
      // the transient podman unit is dropped from the failed list; the fingerprint keeps the trailing space
      note("failed unit がある", "nixos-upgrade.service "),
      note("restic のバックアップが失敗している", "systemctl status restic-backups-homeserver"),
    ]);
    expect(Buffer.byteLength(r.notes[1].body.split("\n")[1])).toBeLessThanOrEqual(200);
    expect(r.notes[1].body).not.toContain("�");
    if (!HAS_TOKEN) {
      expect(r.notes.every((n) => n.auth === "Bearer")).toBe(true);
      expect(r.stderr).toBe(`cat: ${TOKEN_FILE}: No such file or directory\n`.repeat(8));
    }
    expect(state()).toEqual({ ...FRESH_STATE_LOOPS, "failed-units": "nixos-upgrade.service ", restic: "failed" });
  });

  test("an unchanged repeat within 6 hours is silent, even when counts change", async () => {
    const before = readdirSync(stateDir).map((f) => readFileSync(join(stateDir, f), "utf8"));
    fixture([...JOURNAL, fail("romm-db.service", 8)], FAILED1, 0);
    const r = await runAlert();
    expect(r.code).toBe(0);
    expect(r.notes).toEqual([]);
    expect(r.stderr).toBe("");
    expect(readdirSync(stateDir).map((f) => readFileSync(join(stateDir, f), "utf8"))).toEqual(before);
  });

  test("a changed failed-unit list notifies at once", async () => {
    fixture(JOURNAL, FAILED2, 0);
    const r = await runAlert();
    expect(r.notes).toMatchObject([note("failed unit がある", "foo@bar.service nixos-upgrade.service ")]);
    expect(state()["failed-units"]).toBe("foo@bar.service nixos-upgrade.service ");
  });

  test("state older than 6 hours notifies again", async () => {
    ageState(1000);
    fixture(JOURNAL, FAILED2, 0);
    const r = await runAlert();
    expect(r.notes.map((n) => n.title)).toEqual([
      "Home Assistant が recovery mode に落ちた",
      "コンテナの bind mount 先が無い",
      "メモリ不足でプロセスが強制終了された",
      "romm-db.service が失敗を繰り返している",
      "zz-db.service が失敗を繰り返している",
      "attic-db.service が失敗を繰り返している",
      "failed unit がある",
      "restic のバックアップが失敗している",
    ]);
    const now = Math.floor(Date.now() / 1000);
    for (const f of readdirSync(stateDir)) {
      const at = Number(readFileSync(join(stateDir, f), "utf8").split("\t")[0]);
      expect(Math.abs(at - now)).toBeLessThan(60);
    }
  });

  test("a quiet run clears every record and sends nothing", async () => {
    fixture([], [], 1);
    const r = await runAlert();
    expect(r.code).toBe(0);
    expect(r.notes).toEqual([]);
    expect(r.calls).toEqual(STUB_CALLS("-15min"));
    expect(readdirSync(stateDir)).toEqual([]);
  });

  test("after clearing, a recurrence notifies without waiting", async () => {
    fixture(["Oct 23 11:00:00 hs hass[1]: Activating recovery mode"], [], 1);
    const r = await runAlert();
    expect(r.notes).toMatchObject([note("Home Assistant が recovery mode に落ちた", "直近 15min で 1 件\nOct 23 11:00:00 hs hass[1]: Activating recovery mode")]);
  });

  test("the first argument is the journalctl window and appears in the text", async () => {
    rmSync(stateDir, { recursive: true, force: true });
    fixture(JOURNAL, [], 1);
    const r = await runAlert(["-2h"]);
    expect(r.calls).toEqual(STUB_CALLS("-2h"));
    expect(r.notes).toMatchObject(expectedFresh("2h"));
    expect(state()).toEqual(FRESH_STATE_LOOPS);
  });
});

describe("restart-loop detection and the podman transient-unit filter", () => {
  beforeEach(() => {
    rmSync(stateDir, { recursive: true, force: true });
  });

  test("only <64 hex>-<hex>.service is treated as transient", async () => {
    const units = [
      TRANSIENT_UNIT, // skipped
      `${HEX64}-8a155e74d0379d.service`, // skipped: %x drops leading zeros (2026-10-23, dawarich_app)
      `${HEX64}-0123456789abcdef0.service`, // skipped: the suffix length is not checked
      `${"b".repeat(63)}-0123456789abcdef.service`, // 63 hex: a real unit
      `${"A".repeat(64)}-0123456789ABCDEF.service`, // uppercase: a real unit
      `${HEX64}-.service`, // no suffix: a real unit
      "attic-db.service",
    ];
    fixture(
      units.flatMap((u) => [1, 2, 3, 4, 5].map((m) => fail(u, m))),
      [],
      1,
    );
    const r = await runAlert();
    expect(r.notes.map((n) => n.title)).toEqual([
      // equal counts: sort -rn keeps the reverse name order
      `${"b".repeat(63)}-0123456789abcdef.service が失敗を繰り返している`,
      "attic-db.service が失敗を繰り返している",
      `${HEX64}-.service が失敗を繰り返している`,
      `${"A".repeat(64)}-0123456789ABCDEF.service が失敗を繰り返している`,
    ]);
    expect(r.notes[0].body).toBe("直近 15min で 5 回失敗。稼働中に見えても中身は起動できていない。\n");
    expect(Object.keys(state())).not.toContain(`loop-${TRANSIENT_UNIT}`);
  });

  test("a failed list holding only transient units sends nothing and clears the record", async () => {
    mkdirSync(stateDir, { recursive: true });
    writeFileSync(join(stateDir, "failed-units"), "1000\tnixos-upgrade.service \n");
    fixture([], [`${TRANSIENT_UNIT} loaded failed failed hc`], 1);
    const r = await runAlert();
    expect(r.notes).toEqual([]);
    expect(existsSync(join(stateDir, "failed-units"))).toBe(false);
  });

  test("four failures stay below the threshold, five reach it", async () => {
    fixture([...[1, 2, 3, 4].map((m) => fail("four.service", m)), ...[1, 2, 3, 4, 5].map((m) => fail("five.service", m))], [], 1);
    const r = await runAlert();
    expect(r.notes.map((n) => n.title)).toEqual(["five.service が失敗を繰り返している"]);
    expect(Object.keys(state())).toEqual(["loop-five.service"]);
  });

  test("loop records of units that calmed down are removed, other records are kept", async () => {
    mkdirSync(stateDir, { recursive: true });
    const now = Math.floor(Date.now() / 1000);
    writeFileSync(join(stateDir, "loop-old.service"), `${now}\told.service\n`);
    writeFileSync(join(stateDir, "loop-romm-db.service"), `${now}\tromm-db.service\n`);
    writeFileSync(join(stateDir, "unrelated"), `${now}\tx\n`);
    fixture([1, 2, 3, 4, 5].map((m) => fail("romm-db.service", m)), [], 1);
    const r = await runAlert();
    // romm-db is still looping and was recorded just now: throttled
    expect(r.notes).toEqual([]);
    expect(state()).toEqual({ "loop-romm-db.service": "romm-db.service", unrelated: "x" });
  });

  test("lowercase 'permission denied' matches, other casing does not", async () => {
    fixture(["Oct 23 10:00:00 hs a[1]: Permission Denied", "Oct 23 10:01:00 hs a[1]: open: permission denied"], [], 1);
    const r = await runAlert();
    expect(r.notes).toMatchObject([note("権限まわりで拒否されている", "直近 15min で 1 件\nOct 23 10:01:00 hs a[1]: open: permission denied")]);
    expect(state()).toEqual({ "pattern-permission-denied": "permission denied" });
  });
});
