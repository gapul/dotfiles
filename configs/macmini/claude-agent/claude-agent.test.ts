// Regression tests for claude-agent: the exact sequence of external commands for the main
// scenarios. gh, git, claude, curl, ssh and sleep are fakes (testdata/fake-tools.ts) placed in
// $HOME/.local/bin, which init() puts first on PATH; HOME and XDG_STATE_HOME point into a temp
// dir, so nothing reaches GitHub, the network or the real state directory.
import { afterEach, describe, expect, test } from "bun:test";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  realpathSync,
  rmSync,
  utimesSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const AGENT = join(import.meta.dir, "claude-agent.ts");
const FAKE = join(import.meta.dir, "testdata", "fake-tools.ts");
const REPOS = join(import.meta.dir, "testdata", "repos.json");

interface Call {
  tool: string;
  cwd: string;
  argv: string[];
  stdin?: string;
}
interface Result {
  code: number;
  stdout: string;
  stderr: string;
  calls: Call[];
}

const dirs: string[] = [];
afterEach(() => {
  for (const d of dirs.splice(0)) rmSync(d, { recursive: true, force: true });
});

class Sandbox {
  readonly root = realpathSync(mkdtempSync(join(tmpdir(), "claude-agent-test-")));
  readonly home = join(this.root, "home");
  readonly state = join(this.root, "state", "claude-agent");
  readonly seen = join(this.state, "seen");
  readonly fake = join(this.root, "fake");
  readonly cwd = join(this.root, "cwd");
  readonly repo = join(this.state, "repos", "gapul__demo");
  readonly callLog = join(this.root, "calls.jsonl");

  constructor() {
    dirs.push(this.root);
    const bin = join(this.home, ".local", "bin");
    for (const d of [bin, this.seen, this.fake, this.cwd]) mkdirSync(d, { recursive: true });
    for (const t of ["gh", "git", "claude", "curl", "ssh", "sleep"]) {
      writeFileSync(join(bin, t), `#!/bin/sh\nexec "${process.execPath}" --no-env-file "${FAKE}" ${t} "$@"\n`);
      chmodSync(join(bin, t), 0o755);
    }
    writeFileSync(this.callLog, "");
  }

  // A bootstrap file two hours old: issues created since then count as new.
  bootstrap(content = `${Math.floor(Date.now() / 1000) - 7200}\n`): this {
    writeFileSync(join(this.seen, "gapul__demo__bootstrap"), content);
    return this;
  }

  spawn(args: string[], scen = "", extraEnv: Record<string, string> = {}) {
    return Bun.spawn([process.execPath, "--no-env-file", AGENT, ...args], {
      cwd: this.cwd,
      env: {
        HOME: this.home,
        USER: "gapul",
        LOGNAME: "gapul",
        TMPDIR: join(this.root, "cwd"),
        TZ: "Asia/Tokyo",
        PATH: "/usr/bin:/bin",
        XDG_STATE_HOME: join(this.root, "state"),
        CLAUDE_AGENT_REPOS: REPOS,
        STUB_LOG: this.callLog,
        STUB_STATE: this.fake,
        SCEN: scen,
        ...extraEnv,
      },
      stdin: "ignore",
      stdout: "pipe",
      stderr: "pipe",
    });
  }

  async run(args: string[], scen = "", extraEnv: Record<string, string> = {}): Promise<Result> {
    const p = this.spawn(args, scen, extraEnv);
    const [stdout, stderr, code] = await Promise.all([new Response(p.stdout).text(), new Response(p.stderr).text(), p.exited]);
    return { code, stdout: this.strip(stdout), stderr: this.strip(stderr), calls: this.calls() };
  }

  calls(): Call[] {
    return readFileSync(this.callLog, "utf8")
      .split("\n")
      .filter((l) => l !== "")
      .map((l) => JSON.parse(l) as Call);
  }

  // Log lines without their timestamps, paths relative to the sandbox.
  strip(s: string): string {
    return s.replace(/^\[\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\] /gm, "").replaceAll(this.root, "<R>");
  }

  seenKeys(): string[] {
    return readdirSync(this.seen).sort();
  }
}

// [where, tool, ...argv] with the claude prompt elided; "." is the caller's directory and
// "repo" the agent's working copy.
function steps(sb: Sandbox, calls: Call[]): string[][] {
  return calls.map((c) => {
    const where = c.cwd === sb.cwd ? "." : c.cwd === sb.repo ? "repo" : c.cwd;
    const argv = c.tool === "claude" ? ["-p", "<prompt>", ...c.argv.slice(2)] : c.argv;
    return [where, c.tool, ...argv];
  });
}

const PREPARE = (ref: string): string[][] => [
  ["repo", "git", "config", "--local", "credential.helper", ""],
  ["repo", "git", "config", "--local", "user.name", "claude-macmini[bot]"],
  ["repo", "git", "config", "--local", "user.email", "claude-macmini@users.noreply.github.com"],
  ["repo", "git", "remote", "set-url", "origin", "https://x-access-token:ghs_FAKE@github.com/gapul/demo.git"],
  ["repo", "git", "fetch", "--quiet", "--prune", "origin"],
  ["repo", "git", "reset", "--quiet", "--hard", "HEAD"],
  ["repo", "git", "clean", "--quiet", "-fd"],
  ["repo", "git", "checkout", "--quiet", "-B", "__base", ref],
];

const POLL_LISTS: string[][] = [
  [
    ".",
    "gh",
    "issue",
    "list",
    "--repo",
    "gapul/demo",
    "--state",
    "open",
    "--limit",
    "30",
    "--json",
    "number,createdAt,updatedAt,labels",
    "-q",
    '.[] | [(.number|tostring), .createdAt, .updatedAt, ([.labels[].name]|join(","))] | @tsv',
  ],
  [
    ".",
    "gh",
    "run",
    "list",
    "--repo",
    "gapul/demo",
    "--status",
    "failure",
    "--limit",
    "20",
    "--json",
    "databaseId,createdAt",
    "-q",
    ".[] | [(.databaseId|tostring), .createdAt] | @tsv",
  ],
  [
    ".",
    "gh",
    "pr",
    "list",
    "--repo",
    "gapul/demo",
    "--state",
    "open",
    "--limit",
    "30",
    "--json",
    "number,headRefOid,isDraft",
    "-q",
    ".[] | [(.number|tostring), .headRefOid, (.isDraft|tostring)] | @tsv",
  ],
];

// The "→ run-autofix.ts gapul/demo issue:3" lines the poller logs for each dispatch.
const dispatched = (stdout: string): string[] =>
  stdout
    .split("\n")
    .filter((l) => l.startsWith("→ "))
    .map((l) => l.replace(/^→ \S*\/(run-\w+)\.ts /, "$1 "));

describe("entry point", () => {
  test("help and an unknown command", async () => {
    const sb = new Sandbox();
    const help = await sb.run(["help"]);
    expect(help.code).toBe(0);
    expect(help.stdout).toContain("claude-agent poll ");
    const bad = await sb.run(["frobnicate"]);
    expect(bad.code).toBe(2);
    expect(bad.stdout).toContain("claude-agent poll ");
    expect(sb.calls()).toEqual([]);
  });

  test("pause stops the poller before it calls anything; resume clears it", async () => {
    const sb = new Sandbox().bootstrap();
    expect((await sb.run(["pause"])).stdout).toBe("Stopped. Start again with claude-agent resume.\n");
    expect(existsSync(join(sb.state, "PAUSE"))).toBe(true);
    const r = await sb.run(["poll"]);
    expect(r.code).toBe(0);
    expect(r.stdout).toBe("PAUSE file present, doing nothing\n");
    expect(r.calls).toEqual([]);
    await sb.run(["resume"]);
    expect(existsSync(join(sb.state, "PAUSE"))).toBe(false);
  });
});

describe("poll", () => {
  test("nothing to do: only the three listings, and the actions-only repo is skipped", async () => {
    const sb = new Sandbox().bootstrap();
    const r = await sb.run(["poll"], "poll-nowork");
    expect(r.code).toBe(0);
    expect(r.stdout).toBe("trigger=actions, the poller leaves this one alone: gapul/actions-only\npoll finished\n");
    expect(steps(sb, r.calls)).toEqual([[".", "gh", "auth", "token"], ...POLL_LISTS]);
    expect(existsSync(join(sb.state, "poller.lock"))).toBe(false);
  });

  test("first pass records what exists and dispatches nothing", async () => {
    const sb = new Sandbox();
    const r = await sb.run(["poll"], "poll-work");
    expect(r.code).toBe(0);
    expect(dispatched(r.stdout)).toEqual([]);
    expect(r.stdout).toContain("first pass, recording the current state only: gapul/demo\n");
    expect(r.calls.map((c) => c.argv.slice(0, 3).join(" "))).toEqual([
      "auth token",
      "issue list --repo",
      "issue view 1",
      "issue view 2",
      "run list --repo",
      "pr list --repo",
    ]);
    expect(sb.seenKeys()).toEqual([
      "gapul__demo__bootstrap",
      "gapul__demo__issue-1__2026-10-23T01:00:00Z",
      "gapul__demo__issue-2__2026-10-23T01:00:00Z",
      "gapul__demo__pr-8__cafe",
      "gapul__demo__pr-9__beef",
      "gapul__demo__run-100",
      "gapul__demo__run-101",
    ]);
  });

  test("an empty bootstrap file makes no issue count as new", async () => {
    // bash's [ "$c" -gt "" ] was false; Number("") would be 0 and make every issue new.
    const sb = new Sandbox().bootstrap("");
    const r = await sb.run(["poll"], "poll-work", { CLAUDE_AGENT_DRY_RUN: "1" });
    expect(r.code).toBe(0);
    expect(dispatched(r.stdout)).toEqual([
      "run-autofix gapul/demo issue:3",
      "run-autofix gapul/demo issue:6",
      "run-autofix gapul/demo run:201",
      "run-review gapul/demo 8",
      "run-review gapul/demo 11",
    ]);
    expect(r.calls.some((c) => c.tool === "claude")).toBe(false);
  });

  test("dispatches new, labelled and answered issues, recent runs and ready PRs; claude never sees the work list", async () => {
    const sb = new Sandbox().bootstrap();
    const r = await sb.run(["poll"], "poll-work");
    expect(r.code).toBe(0);
    // 1 is new, 3 got an answer, 6 is labelled claude-fix; 2 is no-claude, 4 waits on its
    // asker, 7 is old. Run 202 is backlog. PR 10 is a draft.
    expect(dispatched(r.stdout)).toEqual([
      "run-autofix gapul/demo issue:1",
      "run-autofix gapul/demo issue:3",
      "run-autofix gapul/demo issue:6",
      "run-autofix gapul/demo run:201",
      "run-review gapul/demo 8",
      "run-review gapul/demo 11",
    ]);
    expect(r.stdout).not.toContain("WARN");
    const claude = r.calls.filter((c) => c.tool === "claude");
    expect(claude).toHaveLength(6);
    // The bash poller fed its loop from a process substitution, and the first claude -p read
    // the rest of the list from stdin: later items were skipped and ended up in the prompt.
    for (const c of claude) expect(c.stdin).toBe("");
    expect(sb.seenKeys()).toContain("gapul__demo__run-202");
    expect(existsSync(join(sb.state, "poller.lock"))).toBe(false);
    expect(existsSync(join(sb.state, "claude.lock"))).toBe(false);
  });

  test("a held poller lock means no work at all", async () => {
    const sb = new Sandbox().bootstrap();
    mkdirSync(join(sb.state, "poller.lock"));
    const r = await sb.run(["poll"], "poll-work");
    expect(r.code).toBe(0);
    expect(r.stdout).toBe("the previous poll is still running\n");
    expect(r.calls).toEqual([]);
    expect(existsSync(join(sb.state, "poller.lock"))).toBe(true);
  });
});

describe("autofix", () => {
  test("a failed CI run on the base branch becomes a claude/ci-<id> branch and a PR", async () => {
    const sb = new Sandbox();
    const r = await sb.run(["autofix", "gapul/demo", "run:555"], "ci-fix");
    expect(r.code).toBe(0);
    expect(r.stdout).toBe(
      "cloning gapul/demo\nrunning claude: gapul/demo CI CI (run 555)\ndone: https://github.com/gapul/demo/pull/77\n",
    );
    expect(steps(sb, r.calls)).toEqual([
      [".", "gh", "auth", "token"],
      [".", "gh", "run", "view", "555", "--repo", "gapul/demo", "--json", "databaseId,workflowName,headBranch,headSha,conclusion,event,createdAt"],
      [".", "gh", "api", "repos/gapul/demo/actions/runs/555", "-q", ".head_repository.full_name"],
      [
        ".",
        "gh",
        "run",
        "list",
        "--repo",
        "gapul/demo",
        "--workflow",
        "CI",
        "--branch",
        "main",
        "--limit",
        "10",
        "--json",
        "databaseId,conclusion,createdAt",
        "-q",
        '[.[] | select(.databaseId > 555 and .conclusion == "success")] | length',
      ],
      [".", "gh", "run", "view", "555", "--repo", "gapul/demo", "--log-failed"],
      [".", "git", "clone", "--quiet", "https://github.com/gapul/demo.git", sb.repo],
      ...PREPARE("abc123"),
      ["repo", "git", "checkout", "--quiet", "-B", "claude/ci-555"],
      ["repo", "claude", "-p", "<prompt>", "--dangerously-skip-permissions", "--max-turns", "60"],
      ["repo", "git", "status", "--porcelain"],
      ["repo", "git", "add", "-A"],
      [
        "repo",
        "git",
        "commit",
        "-q",
        "-m",
        "fix(ci): repair the failing CI run\n\nFailed run: https://github.com/gapul/demo/actions/runs/555\n\n🤖 auto-fixed by Claude Code on macmini",
      ],
      ["repo", "git", "push", "origin", "claude/ci-555"],
      ["repo", "gh", "pr", "list", "--repo", "gapul/demo", "--head", "claude/ci-555", "--json", "url", "-q", ".[0].url"],
      [
        "repo",
        "gh",
        "pr",
        "create",
        "--repo",
        "gapul/demo",
        "--base",
        "main",
        "--head",
        "claude/ci-555",
        "--title",
        "fix(ci): repair the failing CI run",
        "--body",
        "main で「CI」が失敗していたので直しました。\n\n失敗した run: https://github.com/gapul/demo/actions/runs/555\n\n🤖 Claude Code (macmini) による自動修正。\n<!-- claude-bot -->",
      ],
    ]);
    const prompt = r.calls.find((c) => c.tool === "claude")?.argv[1] ?? "";
    expect(prompt).toContain("ワークフロー「CI」が、ブランチ main (commit abc123) で失敗しました。");
    // Only the last 400 lines of the failure log go in.
    expect(prompt).toContain("test\tline 51\n");
    expect(prompt).not.toContain("test\tline 50\n");
    expect(prompt).toContain("error: expected 1, got 2");
    expect(prompt).toContain("- 検証: run just test");
    expect(readFileSync(join(sb.seen, "attempts__gapul__demo__ci__CI__main"), "utf8")).toBe("1\n");
    expect(sb.seenKeys()).toContain("gapul__demo__run-555");
    expect(existsSync(join(sb.state, "claude.lock"))).toBe(false);
  });

  test("a run from a fork is recorded and left alone", async () => {
    const sb = new Sandbox();
    const r = await sb.run(["autofix", "gapul/demo", "run:555"], "ci-fork");
    expect(r.code).toBe(0);
    expect(r.stdout).toBe("run 555 is from someone/demo, not gapul/demo; leaving it alone\n");
    expect(r.calls.map((c) => c.tool)).toEqual(["gh", "gh", "gh"]);
    expect(sb.seenKeys()).toEqual(["gapul__demo__run-555"]);
  });

  test("an outside author's issue never reaches claude", async () => {
    const sb = new Sandbox();
    const r = await sb.run(["autofix", "gapul/demo", "issue:5"], "issue-outsider");
    expect(r.code).toBe(0);
    expect(r.stdout).toBe("issue #5 is by an outside author (NONE), leaving it alone\n");
    expect(steps(sb, r.calls)).toEqual([
      [".", "gh", "auth", "token"],
      [".", "gh", "issue", "view", "5", "--repo", "gapul/demo", "--json", "number,title,body,state,updatedAt,labels"],
      [".", "gh", "api", "repos/gapul/demo/issues/5", "-q", ".author_association"],
    ]);
  });

  test("a repository not in repos.json (or disabled) is not touched", async () => {
    const sb = new Sandbox();
    const r = await sb.run(["autofix", "gapul/off", "run:555"], "ci-fix");
    expect(r.code).toBe(0);
    expect(r.stdout).toBe("not in repos.json, doing nothing: gapul/off\n");
    expect(r.calls).toEqual([]);
  });

  test("a held claude lock defers the job", async () => {
    const sb = new Sandbox();
    mkdirSync(join(sb.state, "claude.lock"));
    const r = await sb.run(["autofix", "gapul/demo", "run:555"], "ci-fix");
    expect(r.code).toBe(0);
    expect(r.stdout).toBe("another claude is running, deferring: gapul/demo run:555\n");
    expect(steps(sb, r.calls)).toEqual([[".", "gh", "auth", "token"]]);
    expect(existsSync(join(sb.state, "claude.lock"))).toBe(true);
  });

  test("a stale lock is reclaimed", async () => {
    const sb = new Sandbox();
    const lock = join(sb.state, "claude.lock");
    mkdirSync(lock);
    const old = new Date(Date.now() - 2 * 3600 * 1000);
    utimesSync(lock, old, old);
    const r = await sb.run(["autofix", "gapul/demo", "run:555"], "ci-fork");
    expect(r.stdout).toStartWith("reclaiming a stale lock: claude\n");
    expect(existsSync(lock)).toBe(false);
  });

  test("SIGTERM during the claude run takes effect when it returns and releases the lock", async () => {
    const sb = new Sandbox();
    const p = sb.spawn(["autofix", "gapul/demo", "run:555"], "slow-claude");
    const started = join(sb.fake, "claude-started");
    for (let i = 0; i < 500 && !existsSync(started); i++) await Bun.sleep(10);
    expect(existsSync(started)).toBe(true);
    expect(existsSync(join(sb.state, "claude.lock"))).toBe(true);
    p.kill("SIGTERM");
    // Give the handler a moment to (wrongly) act before claude returns.
    await Bun.sleep(100);
    expect(p.exitCode).toBeNull();
    writeFileSync(join(sb.fake, "release"), "");
    expect(await p.exited).toBe(143);
    expect(existsSync(join(sb.state, "claude.lock"))).toBe(false);
    // Nothing after claude: no commit, no push.
    expect(sb.calls().at(-1)?.tool).toBe("claude");
  });
});

describe("review", () => {
  test("a pull request is checked out read-only and reviewed with COMMENT only", async () => {
    const sb = new Sandbox();
    const r = await sb.run(["review", "gapul/demo", "9"], "review-post");
    expect(r.code).toBe(0);
    expect(r.stdout).toBe(
      "cloning gapul/demo\nchecked PR #9 out into the working tree\nclaude 実行: review gapul/demo PR #9\nposted the review: gapul/demo #9 (2 comments)\n",
    );
    expect(steps(sb, r.calls)).toEqual([
      [".", "gh", "auth", "token"],
      [".", "gh", "api", "user", "-q", ".login"],
      [
        ".",
        "gh",
        "pr",
        "view",
        "9",
        "--repo",
        "gapul/demo",
        "--json",
        "number,title,body,state,isDraft,author,headRefName,headRefOid,labels,additions,deletions,changedFiles",
      ],
      [".", "gh", "pr", "diff", "9", "--repo", "gapul/demo"],
      [".", "git", "clone", "--quiet", "https://github.com/gapul/demo.git", sb.repo],
      ...PREPARE("origin/main"),
      ["repo", "git", "fetch", "--quiet", "origin", "pull/9/head:refs/remotes/pr/9"],
      ["repo", "git", "checkout", "--quiet", "--detach", "refs/remotes/pr/9"],
      ["repo", "claude", "-p", "<prompt>", "--allowedTools", "Read,Grep,Glob", "--max-turns", "40"],
      ["repo", "gh", "api", "repos/gapul/demo/pulls/9/reviews", "--input", "-"],
    ]);
    const prompt = r.calls.find((c) => c.tool === "claude")?.argv[1] ?? "";
    expect(prompt).toContain("あなたは gapul/demo のコードレビュアーです。PR #9 をレビューしてください。");
    expect(prompt).toContain("```diff\ndiff --git a/p.ts b/p.ts\n+++ b/p.ts\n@@ -1,1 +1,2 @@\n x\n+y\n```");
    const payload = JSON.parse(r.calls.at(-1)?.stdin ?? "null");
    expect(payload).toEqual({
      event: "COMMENT",
      body: "🤖 Claude Code (macmini) によるレビューです。\n\nOne real problem.\n\n<!-- claude-bot -->",
      comments: [
        { path: "p.ts", line: 2, side: "RIGHT", body: "**要修正**: y breaks x.\n\n```suggestion\nz\n```" },
        { path: "p.ts", line: 2, side: "RIGHT", body: "minor thing" },
      ],
    });
    expect(sb.seenKeys()).toEqual(["gapul__demo__pr-9__deadbeef"]);
  });
});

describe("monitor", () => {
  test("a healthy pass writes a heartbeat and does not call claude", async () => {
    const sb = new Sandbox();
    writeFileSync(join(sb.state, "agent.log"), "[2026-10-23 10:00:00] poll finished\n");
    const r = await sb.run(["monitor"], "monitor-ok");
    expect(r.code).toBe(0);
    expect(r.stdout).toBe("monitor: healthy (shell pass only, claude not called)\n");
    expect(r.calls.map((c) => c.tool)).not.toContain("claude");
    expect(r.calls.map((c) => c.argv.slice(0, 2).join(" "))).toEqual([
      "auth token",
      "auth status",
      "api repos/gapul/demo/actions/runners",
      "api repos/gapul/demo/actions/runners",
      "issue list",
      "pr list",
      "api repos/gapul/actions-only/actions/runners",
      "api repos/gapul/actions-only/actions/runners",
      "issue list",
      "pr list",
    ]);
    expect(existsSync(join(sb.state, "monitor.heartbeat"))).toBe(true);
  });
});
