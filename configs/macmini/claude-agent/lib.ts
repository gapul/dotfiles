// Shared library for claude-agent. Imported by poller / autofix / review / monitor.
//
// There are two callers: launchd on the mac mini (poller and monitor), and GitHub
// Actions on the self-hosted runner that lives on the same machine. Neither gets a
// login shell, so everything the scripts need is set up here.
//
// Ported from lib.sh. External tools (gh, git, claude, curl) are still run as commands
// with the same argv the shell version used, so the tests that put fakes first on PATH
// see exactly what a real run would do. The jq/date/find/grep plumbing became plain code.
import {
  accessSync,
  appendFileSync,
  closeSync,
  constants,
  existsSync,
  mkdirSync,
  mkdtempSync,
  openSync,
  readFileSync,
  rmSync,
  rmdirSync,
  statSync,
  writeFileSync,
  writeSync,
} from "node:fs";
import { constants as osConstants, tmpdir, userInfo } from "node:os";
import { dirname, join } from "node:path";

export const MARK = "<!-- claude-bot -->";
export const AGENT_DIR = import.meta.dir;

// Filled in by init(), the equivalent of sourcing lib.sh.
export let REPOS_JSON = "";
export let STATE_DIR = "";
export let SEEN_DIR = "";
export let WORK_DIR = "";
export let LOG_FILE = "";
let DRY_RUN = "0";
let GH_PUSH_TOKEN = "";

const env = process.env;

export function init(): void {
  // LANG has to be set. With an empty locale, bash swallows a multi-byte character
  // that follows a variable reference into the variable's name: `$ts。` becomes
  // `ts。: unbound variable` and the script dies under `set -u`. The predecessor of
  // this agent spent a full day dead that way (2026-09).
  // (That trap was bash's; the variables are still exported for git, gh and claude.)
  env.LANG = env.LANG || "en_US.UTF-8";
  env.LC_ALL = env.LC_ALL || "en_US.UTF-8";

  env.PATH = `${env.HOME}/.local/bin:/etc/profiles/per-user/${userInfo().username}/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin`;

  // Claude's subscription OAuth credentials. launchd and the runner do not carry this,
  // so state it explicitly — without it every claude call dies with "Not logged in".
  env.CLAUDE_CONFIG_DIR = env.CLAUDE_CONFIG_DIR || `${env.HOME}/.config/claude`;

  // The mini is headless, so there is no interactive login to authenticate through.
  // Auth comes from a token minted by `claude setup-token`, placed by sops at
  // activation time (secrets/common.yaml, key claude_code_oauth_token). The keychain
  // route does not work over SSH.
  const tokenFile = `${env.CLAUDE_CONFIG_DIR}/oauth-token`;
  if (!env.CLAUDE_CODE_OAUTH_TOKEN && readable(tokenFile)) {
    env.CLAUDE_CODE_OAUTH_TOKEN = chomp(readFileSync(tokenFile, "utf8"));
  }

  REPOS_JSON = env.CLAUDE_AGENT_REPOS || `${AGENT_DIR}/repos.json`;
  STATE_DIR = `${env.XDG_STATE_HOME || `${env.HOME}/.local/state`}/claude-agent`;
  SEEN_DIR = `${STATE_DIR}/seen`;
  WORK_DIR = `${STATE_DIR}/repos`;
  LOG_FILE = `${STATE_DIR}/agent.log`;
  // Log what would have happened and change nothing. This is how the agent is rolled
  // out: watch it for a day before letting it post anything.
  DRY_RUN = env.CLAUDE_AGENT_DRY_RUN || "0";

  mkdirSync(SEEN_DIR, { recursive: true });
  mkdirSync(WORK_DIR, { recursive: true });
}

// --- small shell equivalents ---------------------------------------------

// Strip trailing newlines, as $(...) does.
export const chomp = (s: string): string => s.replace(/\n+$/, "");

export function readable(path: string): boolean {
  try {
    accessSync(path, constants.R_OK);
    return statSync(path).isFile();
  } catch {
    return false;
  }
}

export function isDir(path: string): boolean {
  try {
    return statSync(path).isDirectory();
  } catch {
    return false;
  }
}

// `$(cat file 2>/dev/null)`; undefined when it cannot be read.
export function cat(path: string): string | undefined {
  try {
    return chomp(readFileSync(path, "utf8"));
  } catch {
    return undefined;
  }
}

export const nowSec = (): number => Math.floor(Date.now() / 1000);

const pad = (n: number): string => String(n).padStart(2, "0");

// date '+%Y-%m-%d %H:%M:%S' (local time)
export function timestamp(d = new Date()): string {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}

// date +%Y%m%d-%H%M%S (local time)
export function compactStamp(d = new Date()): string {
  return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
}

// Age in whole seconds of a path's mtime; undefined when it does not exist.
export function ageSec(path: string): number | undefined {
  try {
    return nowSec() - Math.floor(statSync(path).mtimeMs / 1000);
  } catch {
    return undefined;
  }
}

// BSD find's -mmin +n / -mtime +n: the age rounded up to whole units is more than n.
export function olderThan(path: string, n: number, unitSec: number): boolean {
  const age = ageSec(path);
  return age !== undefined && Math.ceil(age / unitSec) > n;
}

// Lines of command output as `while read` sees them: a last line with no newline is
// not read.
export function readLines(s: string): string[] {
  const lines = s.split("\n");
  lines.pop();
  return lines;
}

// `read -r a b c` with a whitespace IFS: leading and trailing separators are dropped,
// runs of them count as one, and the last variable takes the rest of the line.
export function readFields(line: string, n: number, ifs = " \t\n"): string[] {
  const isSep = (c: string): boolean => ifs.includes(c);
  let i = 0;
  let end = line.length;
  while (i < end && isSep(line[i])) i++;
  while (end > i && isSep(line[end - 1])) end--;
  const out: string[] = [];
  for (let v = 0; v < n - 1; v++) {
    let j = i;
    while (j < end && !isSep(line[j])) j++;
    out.push(line.slice(i, j));
    i = j;
    while (i < end && isSep(line[i])) i++;
  }
  out.push(line.slice(i, end));
  return out;
}

// Unquoted $(...) in a for loop: split on whitespace.
export const words = (s: string): string[] => s.split(/[ \t\n]+/).filter((w) => w !== "");

// The last line of a file starting with `prefix`, with the prefix and the whitespace
// after it removed: grep -a "^PREFIX:" | tail -1 | sed 's/^PREFIX:[[:space:]]*//'
export function lastTagged(path: string, prefix: string): string {
  let text: string;
  try {
    text = readFileSync(path, "utf8");
  } catch {
    return "";
  }
  const hits = text.split("\n").filter((l) => l.startsWith(prefix));
  if (hits.length === 0) return "";
  return chomp(hits[hits.length - 1].slice(prefix.length).replace(/^\s+/, ""));
}

// tail -n N of a text, as lines
export function tailLines(text: string, n: number): string[] {
  if (text === "") return [];
  const lines = (text.endsWith("\n") ? text.slice(0, -1) : text).split("\n");
  return lines.slice(-n);
}

// jq -r of a value
export function jqRaw(v: unknown): string {
  if (typeof v === "string") return v;
  if (v === undefined || v === null) return "null";
  return JSON.stringify(v, null, 2);
}

// --- running commands ------------------------------------------------------

type Stdio = "inherit" | "ignore" | "pipe" | number;
export interface RunOpts {
  stdin?: "inherit" | "ignore" | string;
  stdout?: Stdio;
  stderr?: Stdio;
}
export interface RunResult {
  code: number;
  stdout: string;
}

// Run a command the way bash would: looked up on the PATH set by init(), with the
// current environment and working directory. A missing command is 127.
//
// Asynchronous on purpose: a synchronous spawn never lets the event loop run, so a
// SIGTERM handler installed by acquireLock() would never fire and the job would carry
// on after launchd asked it to stop. A signal that arrives while a command runs is
// acted on once it returns, which is what bash did with its trap.
export async function run(cmd: string[], opts: RunOpts = {}): Promise<RunResult> {
  const exe = Bun.which(cmd[0], { PATH: env.PATH ?? "" });
  if (!exe) {
    if (opts.stderr !== "ignore") writeSync(2, `${cmd[0]}: command not found\n`);
    return { code: 127, stdout: "" };
  }
  const stdin = opts.stdin ?? "inherit";
  children++;
  const p = Bun.spawn([exe, ...cmd.slice(1)], {
    cwd: process.cwd(),
    env: { ...env },
    stdin: stdin === "inherit" || stdin === "ignore" ? stdin : Buffer.from(stdin),
    stdout: opts.stdout ?? "inherit",
    stderr: opts.stderr ?? "inherit",
  });
  const stdout = p.stdout instanceof ReadableStream ? new Response(p.stdout).text() : Promise.resolve("");
  const exitCode = await p.exited;
  const text = await stdout;
  children--;
  if (pendingSignal) {
    releaseLock();
    process.exit(143);
  }
  // Killed by a signal: report 128+n as the shell does.
  const sig = p.signalCode ? (osConstants.signals as Record<string, number>)[p.signalCode] : undefined;
  return { code: p.signalCode ? 128 + (sig ?? 15) : exitCode, stdout: text };
}

export const ok = async (cmd: string[], opts: RunOpts = {}): Promise<boolean> => (await run(cmd, opts)).code === 0;

// $(cmd 2>/dev/null)
export const capture = async (cmd: string[]): Promise<string> =>
  chomp((await run(cmd, { stdout: "pipe", stderr: "ignore" })).stdout);

// $(cmd), with stderr left on the terminal
export const captureStdout = async (cmd: string[]): Promise<string> => chomp((await run(cmd, { stdout: "pipe" })).stdout);

// $(cmd 2>/dev/null || echo fallback)
export async function captureOr(cmd: string[], fallback: string): Promise<string> {
  const r = await run(cmd, { stdout: "pipe", stderr: "ignore" });
  return chomp(r.code === 0 ? r.stdout : `${r.stdout}${fallback}\n`);
}

// cmd > file 2>&1 (or only stdout into the file, with stderr thrown away)
export async function runToFile(cmd: string[], path: string, opts: { stderr: "same" | "ignore" }): Promise<number> {
  const fd = openSync(path, "w");
  try {
    return (await run(cmd, { stdout: fd, stderr: opts.stderr === "same" ? fd : "ignore" })).code;
  } finally {
    closeSync(fd);
  }
}

// $(cmd 2>&1): stdout and stderr interleaved as they were written.
export async function captureMerged(cmd: string[]): Promise<{ code: number; out: string }> {
  const dir = mkdtempSync(join(tmpdir(), "claude-agent-"));
  try {
    const f = join(dir, "out");
    const code = await runToFile(cmd, f, { stderr: "same" });
    return { code, out: chomp(readFileSync(f, "utf8")) };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// --- logging ---------------------------------------------------------------

// fd is 1 normally; openOrCreatePr logs to stderr, as the shell version did to keep its stdout for the URL.
export function log(msg: string, fd = 1): void {
  appendFileSync(LOG_FILE, `[${timestamp()}] ${msg}\n`);
  writeSync(fd, `[${timestamp()}] ${msg}\n`);
}

export const dry = (): boolean => DRY_RUN !== "0";
export const isTrue = (v: string | undefined): boolean => v === "true" || v === "1" || v === "yes";

// Notification. Reads the same ntfy files restic and dotfiles-pull use. There is no
// screen on this machine to put a dialog on, so this is the only way anything gets
// noticed. If it is not configured, log and carry on rather than fail.
export async function notify(title: string, body: string, prio = "default"): Promise<void> {
  log(`NOTIFY[${prio}] ${title}: ${body}`);
  const urlF = `${env.HOME}/.config/ntfy/url`;
  const tokF = `${env.HOME}/.config/ntfy/token`;
  if (!readable(urlF) || !readable(tokF)) return;
  await run(
    [
      "curl",
      "-fsS",
      "--max-time",
      "15",
      "-o",
      "/dev/null",
      "-H",
      `Authorization: Bearer ${cat(tokF) ?? ""}`,
      "-H",
      "Title: claude-agent (macmini)",
      "-H",
      `Priority: ${prio}`,
      "-H",
      "Tags: warning",
      "-d",
      `${title}\n${body}`,
      cat(urlF) ?? "",
    ],
    { stdout: "ignore", stderr: "ignore" },
  );
}

// --- kill switch --------------------------------------------------------
// A PAUSE file stops everything. To stop one issue or PR, label it no-claude.
export function paused(): boolean {
  if (existsSync(`${STATE_DIR}/PAUSE`)) {
    log("PAUSE file present, doing nothing");
    return true;
  }
  return false;
}

// --- GitHub auth --------------------------------------------------------
// `gh auth token` echoes back whatever is in GITHUB_TOKEN, so clear that first to
// get at the real user token. The Actions GITHUB_TOKEN has no workflow scope, and a
// push that touches .github/workflows is rejected without it.
//
// `gh auth token` also returns empty on a transient failure. An empty GH_TOKEN takes
// precedence over hosts.yml, so every later gh call would run unauthenticated and
// fail. Export only when it is non-empty.
export async function setupGhToken(): Promise<void> {
  delete env.GITHUB_TOKEN;
  const t = await capture(["gh", "auth", "token"]);
  if (t !== "") {
    env.GH_TOKEN = t;
    GH_PUSH_TOKEN = t;
  } else {
    delete env.GH_TOKEN;
    GH_PUSH_TOKEN = "";
    log("WARN: gh auth token came back empty, falling back to hosts.yml");
  }
}

// --- locking ------------------------------------------------------------
// macOS has no flock, so lean on mkdir being atomic. A lock left behind by an
// abnormal exit is reclaimed after a while — being stuck forever is worse than the
// small risk of two runs overlapping.
let lockHeld = "";
let trapsSet = false;
let children = 0;
let pendingSignal = false;
export function acquireLock(name: string, staleMin = 60): boolean {
  const lock = `${STATE_DIR}/${name}.lock`;
  if (isDir(lock) && olderThan(lock, staleMin, 60)) {
    log(`reclaiming a stale lock: ${name}`);
    try {
      rmdirSync(lock);
    } catch {}
  }
  try {
    mkdirSync(lock);
  } catch {
    return false;
  }
  lockHeld = lock;
  if (!trapsSet) {
    trapsSet = true;
    process.on("exit", releaseLock);
    for (const sig of ["SIGINT", "SIGTERM"] as const) {
      process.on(sig, () => {
        // bash ran its trap only after the foreground command returned; run() does the same
        if (children > 0) {
          pendingSignal = true;
          return;
        }
        releaseLock();
        process.exit(143);
      });
    }
  }
  return true;
}
export function releaseLock(): void {
  if (lockHeld) {
    try {
      rmdirSync(lockHeld);
    } catch {}
  }
  lockHeld = "";
}

// --- what has already been handled --------------------------------------
// Keys are repo/kind/id. A PR review key carries the head SHA, so a new push gets
// reviewed again while the same commit never does.
export const seenPath = (key: string): string => `${SEEN_DIR}/${key.replaceAll("/", "__")}`;
export const seen = (key: string): boolean => existsSync(seenPath(key));
export const markSeen = (key: string): void => writeFileSync(seenPath(key), `${nowSec()}\n`);

// --- who may steer claude -----------------------------------------------
// Issues, comments and fork pull requests on a public repository can come from anyone,
// and autofix runs claude with --dangerously-skip-permissions as the login user. Text
// that ends up in its prompt has to come from someone with write access to the repo.
// The values are GitHub's author_association.
export const trustedAssociation = (a: string): boolean => a === "OWNER" || a === "MEMBER" || a === "COLLABORATOR";

// --- repos.json ---------------------------------------------------------
type Entry = Record<string, unknown> | null;

// .repos[] of repos.json; throws where jq would fail.
function entries(): Entry[] {
  const j: unknown = JSON.parse(readFileSync(REPOS_JSON, "utf8"));
  if (j === null || typeof j !== "object" || Array.isArray(j)) throw new Error("cannot index");
  const repos = (j as { repos?: unknown }).repos;
  if (repos === undefined || repos === null || typeof repos !== "object") throw new Error("cannot iterate");
  const list: unknown[] = Array.isArray(repos) ? repos : Object.values(repos);
  for (const e of list) if (e !== null && (typeof e !== "object" || Array.isArray(e))) throw new Error("cannot index");
  return list as Entry[];
}

// First entry for a repository, enabled or not (jq: first(.repos[] | select(.repo == $r))).
export function repoEntry(repo: string): Entry | undefined {
  try {
    return entries().find((e) => e?.repo === repo);
  } catch {
    return undefined;
  }
}

// One line per enabled repository, as `jq -r` prints them.
export function repoList(): string[] {
  try {
    return entries()
      .filter((e) => e?.enabled !== false)
      .map((e) => jqRaw(e?.repo));
  } catch {
    return [];
  }
}

export function repoAllowed(repo: string): boolean {
  try {
    return entries().some((e) => e?.repo === repo && e?.enabled !== false);
  } catch {
    return false;
  }
}

// jq's // treats false as absent, so it cannot be used for boolean policies that
// default to true. Branch on has() instead.
export function policy(repo: string, key: string, def: string): string {
  const x = repoEntry(repo);
  let out: string;
  if (x === undefined || x === null) out = def;
  else if (Object.hasOwn(x, key)) {
    const v = x[key];
    out = typeof v === "string" ? v : JSON.stringify(v);
  } else out = def;
  return chomp(out) || def;
}

// --- working copies -----------------------------------------------------
// Cloning per task is too slow, so keep one checkout per repository and reuse it.
// Only one claude runs at a time (global lock), so nothing contends for the tree.
export const repoDir = (repo: string): string => `${WORK_DIR}/${repo.replaceAll("/", "__")}`;

// Land on a clean checkout of the given ref and cd there. Ignored files
// (node_modules and friends) are kept: removing them only makes every run slower,
// and they are not a source of contamination.
export async function prepareRepo(repo: string, ref: string): Promise<boolean> {
  const dir = repoDir(repo);
  if (!isDir(`${dir}/.git`)) {
    log(`cloning ${repo}`);
    if (!(await ok(["git", "clone", "--quiet", `https://github.com/${repo}.git`, dir]))) return false;
  }
  try {
    process.chdir(dir);
  } catch {
    writeSync(2, `cd: ${dir}: No such file or directory\n`);
    return false;
  }
  // Push with the token embedded in the URL. Under launchd the osxkeychain helper
  // cannot reach the login keychain and fails with "failed to store: -25308".
  await run(["git", "config", "--local", "credential.helper", ""]);
  await run(["git", "config", "--local", "user.name", "claude-macmini[bot]"]);
  await run(["git", "config", "--local", "user.email", "claude-macmini@users.noreply.github.com"]);
  if (GH_PUSH_TOKEN) {
    await run(["git", "remote", "set-url", "origin", `https://x-access-token:${GH_PUSH_TOKEN}@github.com/${repo}.git`]);
  }
  if (!(await ok(["git", "fetch", "--quiet", "--prune", "origin"]))) return false;
  await run(["git", "reset", "--quiet", "--hard", "HEAD"], { stderr: "ignore" });
  await run(["git", "clean", "--quiet", "-fd"], { stderr: "ignore" });
  if (!(await ok(["git", "checkout", "--quiet", "-B", "__base", ref], { stderr: "ignore" }))) {
    log(`ERROR: cannot check out ${ref} in ${repo}`);
    return false;
  }
  return true;
}

// --- running claude -----------------------------------------------------
// First argument is the prompt, second is where to write the output, the rest are
// passed through to claude.
export async function runClaude(prompt: string, out: string, ...args: string[]): Promise<number> {
  if (dry()) {
    log(`DRY-RUN: would call claude here (log=${out}, args=${args.join(" ")})`);
    writeFileSync(out, "DRY-RUN\n");
    return 0;
  }
  const rc = await runToFile(["claude", "-p", prompt, ...args], out, { stderr: "same" });
  // An expired login produces a system that quietly does nothing, so make sure it
  // is impossible to miss.
  if (readFileSync(out, "latin1").includes("Not logged in")) {
    await notify(
      "claude-agent: not authenticated",
      "Claude Code on the mac mini is not logged in. Re-run claude setup-token and update the sops secret.",
      "high",
    );
    return 90;
  }
  return rc;
}

// mkdir -p "$(dirname path)"
export const ensureParent = (path: string): void => void mkdirSync(dirname(path), { recursive: true });
