// Fake gh / git / claude / curl / ssh / sleep for claude-agent.test.ts. The test puts a
// small wrapper per tool first on the agent's PATH ($HOME/.local/bin) that execs this file
// with the tool name. Every call is appended to $STUB_LOG as one JSON line; what each call
// answers is picked by $SCEN. Nothing here touches the network or anything outside
// $STUB_STATE.
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";

const [tool = "", ...argv] = process.argv.slice(2);
const SCEN = process.env.SCEN ?? "";
const STATE = process.env.STUB_STATE ?? "";
const has = (...xs: string[]): boolean => xs.every((x) => argv.includes(x));
const a = argv.join(" ");

// Record stdin where the agent pipes something in (the review payload), and for claude
// always: it must never see the poller's work list (the stdin regression of the bash version).
let stdin: string | undefined;
if ((tool === "gh" && has("--input", "-")) || tool === "claude") stdin = readFileSync(0, "utf8");
appendFileSync(
  process.env.STUB_LOG ?? "/dev/null",
  `${JSON.stringify({ tool, cwd: process.cwd(), argv, ...(stdin !== undefined ? { stdin } : {}) })}\n`,
);

const out = (s: string): void => void process.stdout.write(s);
const iso = (secAgo: number): string => new Date(Date.now() - secAgo * 1000).toISOString().replace(/\.\d+Z$/, "Z");
const work = SCEN.startsWith("poll-work");

function gh(): number {
  if (a === "auth token") {
    out("ghs_FAKE\n");
    return 0;
  }
  if (a === "auth status") return 0;
  if (a === "api user -q .login") {
    out("gapul\n");
    return 0;
  }
  // --- issues
  if (argv[0] === "issue" && argv[1] === "view") {
    if (has("number,title,body,state,updatedAt,labels")) {
      out(
        `${JSON.stringify({
          number: Number(argv[2]),
          title: "Add a dark mode toggle",
          body: "Please add a toggle.\n",
          state: "OPEN",
          updatedAt: "2026-10-23T01:00:00Z",
          labels: [{ name: "claude-fix" }],
        })}\n`,
      );
      return 0;
    }
    if (has("updatedAt")) {
      out(existsSync(`${STATE}/commented`) ? "2026-10-23T02:00:00Z\n" : "2026-10-23T01:00:00Z\n");
      return 0;
    }
    if (has("comments")) {
      // #3: a person answered the bot's question; #4: the bot spoke last
      out(argv[2] === "3" ? "thanks, here is the answer\n" : "question? <!-- claude-bot -->\n");
      return 0;
    }
  }
  if (argv[0] === "issue" && (argv[1] === "comment" || argv[1] === "edit")) {
    writeFileSync(`${STATE}/commented`, "");
    return 0;
  }
  if (argv[0] === "issue" && argv[1] === "list") {
    if (has("--label", "claude-in-progress")) {
      out("0\n");
      return 0;
    }
    if (has("number")) {
      out("1\n2\n");
      return 0;
    }
    // poller TSV: number, createdAt, updatedAt, labels
    if (work) {
      out(
        [
          `1\t${iso(60)}\t2026-10-23T01:00:00Z\t`,
          `2\t${iso(60)}\t2026-10-23T01:00:00Z\tno-claude`,
          `3\t${iso(999999)}\t2026-10-23T01:00:00Z\tbug,claude-needs-info`,
          `4\t${iso(999999)}\t2026-10-23T01:00:00Z\tclaude-needs-info`,
          `6\t${iso(999999)}\t2026-10-23T01:00:00Z\tclaude-fix`,
          `7\t${iso(999999)}\t2026-10-23T01:00:00Z\t`,
          "",
        ].join("\n"),
      );
    }
    return 0;
  }
  if (argv[0] === "api" && /^repos\/[^/]+\/[^/]+\/issues\/\d+$/.test(argv[1] ?? "")) {
    out(SCEN === "issue-outsider" ? "NONE\n" : "OWNER\n");
    return 0;
  }
  if (argv[0] === "api" && argv[1] === "--paginate") {
    out("--- gapul:\nplease make it blue\n");
    return 0;
  }
  // --- runs
  if (argv[0] === "run" && argv[1] === "view") {
    if (has("--log-failed")) {
      out(`${Array.from({ length: 450 }, (_, i) => `test\tline ${i}`).join("\n")}\nerror: expected 1, got 2\n`);
      return 0;
    }
    out(
      `${JSON.stringify({
        databaseId: Number(argv[2]),
        workflowName: "CI",
        headBranch: "main",
        headSha: "abc123",
        conclusion: "failure",
        event: "push",
        createdAt: iso(600),
      })}\n`,
    );
    return 0;
  }
  if (argv[0] === "api" && /actions\/runs\/\d+$/.test(argv[1] ?? "")) {
    out(SCEN === "ci-fork" ? "someone/demo\n" : "gapul/demo\n");
    return 0;
  }
  if (argv[0] === "run" && argv[1] === "list") {
    if (has("--workflow")) {
      out("0\n");
      return 0;
    }
    if (has("databaseId")) {
      out("100\n101\n");
      return 0;
    }
    // 201 failed ten minutes ago; 202 a day ago, which is backlog
    if (work) out(`201\t${iso(600)}\n202\t${iso(86400)}\n`);
    return 0;
  }
  // --- pull requests
  if (argv[0] === "pr" && argv[1] === "list") {
    if (has("--head")) return 0;
    if (has("number,headRefOid")) {
      out("8 cafe\n9 beef\n");
      return 0;
    }
    if (has("headRefName,statusCheckRollup")) {
      out("0\n");
      return 0;
    }
    // #10 is a draft
    if (work) out("8\tcafe\tfalse\n10\tf00d\ttrue\n11\tbead\tfalse\n");
    return 0;
  }
  if (argv[0] === "pr" && argv[1] === "create") {
    out("Creating pull request for claude/x into main\nhttps://github.com/gapul/demo/pull/77\n");
    return 0;
  }
  if (argv[0] === "pr" && argv[1] === "view") {
    out(
      `${JSON.stringify({
        number: Number(argv[2]),
        title: "Refactor parser",
        body: "Splits the parser.\n",
        state: "OPEN",
        isDraft: false,
        author: { login: "gapul" },
        headRefName: "feat/parser",
        headRefOid: argv[2] === "11" ? "bead" : argv[2] === "8" ? "cafe" : "deadbeef",
        labels: [],
        additions: 10,
        deletions: 2,
        changedFiles: 2,
      })}\n`,
    );
    return 0;
  }
  if (argv[0] === "pr" && argv[1] === "diff") {
    out("diff --git a/p.ts b/p.ts\n+++ b/p.ts\n@@ -1,1 +1,2 @@\n x\n+y\n\n");
    return 0;
  }
  if (argv[0] === "api" && /pulls\/\d+\/reviews$/.test(argv[1] ?? "")) return 0;
  if (argv[0] === "pr" && argv[1] === "comment") return 0;
  if (argv[0] === "api" && /actions\/runners$/.test(argv[1] ?? "")) {
    out("1\n");
    return 0;
  }
  process.stderr.write(`fake gh: unhandled: ${a}\n`);
  return 64;
}

function git(): number {
  if (argv[0] === "clone") {
    mkdirSync(`${argv[argv.length - 1]}/.git`, { recursive: true });
    return 0;
  }
  if (argv[0] === "status") {
    if (existsSync(`${STATE}/changed`)) out(" M src/x.ts\n");
    return 0;
  }
  return 0;
}

function claude(): number {
  const prompt = argv[1] ?? "";
  if (SCEN === "slow-claude") {
    // Hold the run open until the test has sent its signal.
    writeFileSync(`${STATE}/claude-started`, "");
    const until = Date.now() + 5000;
    while (!existsSync(`${STATE}/release`) && Date.now() < until) Bun.sleepSync(20);
  }
  if (prompt.includes("コードレビュアー")) {
    const json = JSON.stringify({
      summary: "One real problem.\n",
      comments: [
        { path: "p.ts", line: 2, severity: "blocker", body: "y breaks x.", suggestion: "z" },
        { path: "p.ts", line: "2", severity: "suggestion", body: "minor thing" },
      ],
    });
    // Only the last block counts.
    out(`thinking...\n<<<REVIEW_JSON\n{"draft": true}\nREVIEW_JSON\nfinal:\n<<<REVIEW_JSON\n${json}\nREVIEW_JSON\n`);
    return 0;
  }
  writeFileSync(`${STATE}/changed`, "");
  out("fixed it\n");
  return 0;
}

let code = 0;
switch (tool) {
  case "gh":
    code = gh();
    break;
  case "git":
    code = git();
    break;
  case "claude":
    code = claude();
    break;
  case "curl":
  case "sleep":
    break;
  default:
    // ssh and anything else is never expected
    process.stderr.write(`fake ${tool}: unexpected call\n`);
    code = 99;
}
process.exit(code);
