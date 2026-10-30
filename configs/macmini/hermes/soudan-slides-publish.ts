#!/usr/bin/env bun
// Push the soudan bot's weekly slide draft into the IS-CPU-6/slides repository.
//
// Runs as gapul (nix/home/macmini-soudan-digest.nix) after the bot's Monday cron job, because the
// org has deploy keys disabled and gapul's gh login is the only write access there is; the bot
// never holds it. The files come from the hsoudan sandbox, which strangers can drive, so they
// are read without following symlinks and checked for the second-core words before anything
// is committed (the same list as in soudan-weekly-collect.py).
//
// Usage: soudan-slides-publish.ts [--final]
//   --final: the last attempt of the evening; a missing draft is reported instead of ignored.
//
// Ported from soudan-slides-publish.py. Two deliberate differences: the ntfy Title header is
// sent RFC 2047-encoded (the Python version passed the Japanese title as a raw header value,
// which urllib cannot encode, so every notification was silently dropped), and a FIFO in the
// draft directory is rejected rather than hanging the job (see readPlain).
import {
  closeSync,
  constants,
  existsSync,
  fstatSync,
  lstatSync,
  mkdirSync,
  openSync,
  readdirSync,
  readFileSync,
  readSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { constants as osConstants, homedir } from "node:os";
import { extname, join, relative, sep } from "node:path";

const SRC_ROOT = "/Users/hsoudan/workspace/progress";
const REPO = join(homedir(), ".local/share/soudan-slides");
const REMOTE = "https://github.com/IS-CPU-6/slides.git";
const JST_OFFSET_MS = 9 * 3600 * 1000;
const LIMITS: Record<string, number> = { ".md": 512 * 1024, ".pdf": 50 * 1024 * 1024 };
const SECRET = new RegExp(
  "2nd|２nd|second|セカンド|ヤバコア|SIMT|warp|ワープ|OoO|out.of.order|アウトオブオーダ" +
    "|スーパースカラ|superscalar|VLIW|GPU|アクセラレータ|ベクトル命令|ベクトル演算",
  "iu",
);
const GIT = [
  "git",
  "-c",
  "credential.helper=",
  "-c",
  "credential.helper=!gh auth git-credential",
  "-c",
  "commit.gpgsign=false",
  "-c",
  "user.name=soudan bot",
  "-c",
  "user.email=soudan-bot@users.noreply.github.com",
];

// Raised when a checked command exits non-zero, like subprocess.CalledProcessError.
class CommandError extends Error {}

function pyRepr(s: string): string {
  const q = s.includes("'") && !s.includes('"') ? '"' : "'";
  return q + s.replaceAll("\\", "\\\\").replaceAll(q, `\\${q}`) + q;
}

function run(cmd: string[], opts: { check: boolean; input?: Uint8Array; capture?: boolean }): {
  code: number;
  stdout: Uint8Array;
} {
  const p = Bun.spawnSync(cmd, {
    stdin: opts.input ?? "inherit",
    stdout: opts.capture ? "pipe" : "inherit",
    stderr: opts.capture ? "pipe" : "inherit",
  });
  const code = p.exitCode ?? 1;
  if (opts.check && code !== 0) {
    throw new CommandError(`Command '[${cmd.map(pyRepr).join(", ")}]' returned non-zero exit status ${code}.`);
  }
  return { code, stdout: p.stdout ?? new Uint8Array() };
}

// ntfy decodes RFC 2047 encoded words; header values themselves must stay Latin-1.
const encodeHeader = (v: string): string =>
  /^[\x20-\x7e]*$/.test(v) ? v : `=?UTF-8?B?${Buffer.from(v).toString("base64")}?=`;

async function notify(title: string, body: string): Promise<void> {
  let url: string;
  let token: string;
  try {
    url = readFileSync(join(homedir(), ".config/ntfy/url"), "utf8").trim();
    token = readFileSync(join(homedir(), ".config/ntfy/token"), "utf8").trim();
  } catch {
    return;
  }
  try {
    const r = await fetch(url, {
      method: "POST",
      body,
      headers: {
        Authorization: `Bearer ${token}`,
        Title: encodeHeader(title),
        Tags: "cpuex",
        "Content-Type": "application/x-www-form-urlencoded",
      },
      signal: AbortSignal.timeout(15_000),
    });
    await r.arrayBuffer();
  } catch {
    // best effort, as before
  }
}

async function fail(msg: string): Promise<never> {
  process.stderr.write(`${msg}\n`);
  await notify("進捗スライドを slides repo に上げられない", msg);
  process.exit(1);
}

function errText(e: unknown): string {
  if (e instanceof Error) {
    const n = e as NodeJS.ErrnoException;
    if (n.code && n.path) {
      const errno = (osConstants.errno as Record<string, number>)[n.code];
      const reason = e.message.replace(/^[A-Z]+: /, "").replace(/, \w+ '.*'$/, "");
      return `[Errno ${errno ?? n.code}] ${reason}: ${pyRepr(n.path)}`;
    }
    return e.message;
  }
  return String(e);
}

/** Read a regular file without following a symlink at any step below SRC_ROOT. */
function readPlain(path: string, limit: number): Uint8Array {
  const parts = relative(SRC_ROOT, path).split(sep);
  let cur = SRC_ROOT;
  for (const part of parts.slice(0, -1)) {
    cur = join(cur, part);
    if (!lstatSync(cur).isDirectory()) throw new Error(`${cur} is not a plain directory`);
  }
  // O_NONBLOCK so a FIFO planted in the sandbox fails the regular-file check instead of
  // blocking the open forever (the Python version hung there). No effect on regular files.
  const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const st = fstatSync(fd);
    if (!st.isFile()) throw new Error(`${path} is not a regular file`);
    if (st.size > limit) throw new Error(`${path} is larger than ${limit} bytes`);
    const buf = new Uint8Array(st.size);
    let off = 0;
    while (off < buf.length) {
      const n = readSync(fd, buf, off, buf.length - off, null);
      if (n === 0) break;
      off += n;
    }
    return buf.subarray(0, off);
  } finally {
    closeSync(fd);
  }
}

// Python's sorted() on str: by code point.
function cmp(a: string, b: string): number {
  const x = Array.from(a, (c) => c.codePointAt(0) ?? 0);
  const y = Array.from(b, (c) => c.codePointAt(0) ?? 0);
  for (let i = 0; i < Math.min(x.length, y.length); i++) if (x[i] !== y[i]) return x[i] - y[i];
  return x.length - y.length;
}

async function main(): Promise<void> {
  const final = Bun.argv.slice(2).includes("--final");
  // Today in JST; weekday with Monday = 0, then the next Tuesday (a week out on a Tuesday).
  const now = new Date(Date.now() + JST_OFFSET_MS);
  const weekday = (now.getUTCDay() + 6) % 7;
  const ahead = (((1 - weekday) % 7) + 7) % 7 || 7;
  const target = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + ahead))
    .toISOString()
    .slice(0, 10);
  const src = join(SRC_ROOT, target);

  let names: string[];
  try {
    names = readdirSync(src)
      .filter((n) => /^progress-\p{Nd}+\.(md|pdf)$/u.test(n))
      .sort(cmp);
  } catch {
    names = [];
  }
  if (!names.some((n) => n.endsWith(".md"))) {
    if (final) await fail(`${src} に下書きの md が無い(bot の cron が失敗した?)`);
    return;
  }

  const files = new Map<string, Uint8Array>();
  for (const n of names) {
    try {
      files.set(n, readPlain(join(src, n), LIMITS[extname(n)]));
    } catch (e) {
      await fail(`${n} を読めない: ${errText(e)}`);
    }
  }

  const decoder = new TextDecoder("utf-8");
  for (const [n, data] of files) {
    let text = decoder.decode(data);
    if (n.endsWith(".pdf")) {
      const pdftotext = Bun.which("pdftotext");
      if (!pdftotext) await fail("pdftotext が無いので PDF を確認できない");
      text = decoder.decode(run([pdftotext as string, "-", "-"], { check: true, input: data, capture: true }).stdout);
    }
    const hit = SECRET.exec(text);
    if (hit) await fail(`${n} に 2nd コア関連の語「${hit[0]}」がある。repo には上げていない。`);
  }

  if (!(existsSync(join(REPO, ".git")) && statSync(join(REPO, ".git")).isDirectory())) {
    run([...GIT, "clone", "-q", REMOTE, REPO], { check: true });
  }
  const git = [...GIT, "-C", REPO];
  run([...git, "pull", "-q", "--ff-only"], { check: true });
  const dst = join(REPO, "progress", target);
  mkdirSync(dst, { recursive: true });
  for (const [n, data] of files) writeFileSync(join(dst, n), data);
  run([...git, "add", "progress"], { check: true });
  if (run([...git, "diff", "--cached", "--quiet"], { check: false }).code === 0) return;
  run([...git, "commit", "-q", "-m", `progress ${target}: soudan bot の下書き`], { check: true });
  run([...git, "push", "-q", "origin", "HEAD"], { check: true });
}

try {
  await main();
} catch (e) {
  if (e instanceof CommandError) await fail(`git が失敗した: ${e.message}`);
  throw e;
}
