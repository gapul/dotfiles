#!/usr/bin/env bun
// The entry point for claude-agent. ~/.local/bin/claude-agent points here.
//
// Everything goes through this one command: running it by hand, launchd, and the
// per-repository caller workflow on the self-hosted runner. The real files live in
// the nix store, so updates arrive by rebuilding rather than by editing what is running.
//
// Ported from claude-agent.sh.
import { existsSync, readdirSync, readFileSync, rmSync, writeFileSync, writeSync } from "node:fs";
import { main as monitor } from "./monitor.ts";
import { main as poll } from "./poller.ts";
import { main as autofix } from "./run-autofix.ts";
import { main as review } from "./run-review.ts";
import { LOG_FILE, STATE_DIR, cat, dry, init, isDir, nowSec, repoList, tailLines, timestamp } from "./lib.ts";

const out = (s: string): void => void writeSync(1, `${s}\n`);

function usage(): void {
  out(`claude-agent - automatic fixes and reviews, resident on the mac mini

  claude-agent poll                       walk repos.json and handle what it finds
  claude-agent autofix <repo> issue:<n>   implement an issue and open a pull request
  claude-agent autofix <repo> run:<id>    repair a failed Actions run
  claude-agent review  <repo> <pr>        review a pull request
  claude-agent monitor                    check the agent's own health
  claude-agent status                     show the current state
  claude-agent pause / resume             stop everything / start again

Environment
  CLAUDE_AGENT_DRY_RUN=1   post and push nothing, only log what would have happened
  CLAUDE_AGENT_REPOS=path  use a different repos.json`);
}

function status(): number {
  init();
  out("Repositories:");
  for (const r of repoList()) out(`  ${r}`);
  out("");
  out(existsSync(`${STATE_DIR}/PAUSE`) ? "State: paused" : "State: running");
  if (dry()) out("DRY-RUN is on");
  for (const f of readdirSync(STATE_DIR)
    .filter((f) => f.endsWith(".lock") && !f.startsWith("."))
    .sort()) {
    if (isDir(`${STATE_DIR}/${f}`)) out(`In flight: ${f.slice(0, -".lock".length)}`);
  }
  if (existsSync(`${STATE_DIR}/monitor.heartbeat`)) {
    const at = Number(cat(`${STATE_DIR}/monitor.heartbeat`));
    out(`Last monitor pass: ${Number.isFinite(at) ? timestamp(new Date(at * 1000)) : ""}`);
  }
  out("");
  out("Recent log:");
  let text: string;
  try {
    text = readFileSync(LOG_FILE, "utf8");
  } catch {
    // tail failed, and under pipefail so did the command
    return 1;
  }
  for (const l of tailLines(text, 20)) out(`  ${l}`);
  return 0;
}

const [cmd = "", ...args] = process.argv.slice(2);
let code = 0;
switch (cmd) {
  case "poll":
    code = await poll();
    break;
  case "autofix":
    code = await autofix(args);
    break;
  case "review":
    code = await review(args);
    break;
  case "monitor":
    code = await monitor();
    break;
  case "pause":
    init();
    writeFileSync(`${STATE_DIR}/PAUSE`, `${nowSec()}\n`);
    out("Stopped. Start again with claude-agent resume.");
    break;
  case "resume":
    init();
    rmSync(`${STATE_DIR}/PAUSE`, { force: true });
    out("Started again.");
    break;
  case "status":
    code = status();
    break;
  case "":
  case "-h":
  case "--help":
  case "help":
    usage();
    break;
  default:
    usage();
    code = 2;
}
process.exit(code);
