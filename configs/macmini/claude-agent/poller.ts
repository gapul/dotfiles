#!/usr/bin/env bun
// Walk repos.json and hand anything worth picking up to run-autofix.ts or
// run-review.ts. launchd on the mac mini runs this every five minutes.
//
// This can fire for the same thing as the Actions path (the per-repository caller
// workflow), but both share the same record of what has been handled, so whichever
// gets there first is the only one that acts.
//
// Ported from poller.sh.
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import {
  AGENT_DIR,
  MARK,
  acquireLock,
  capture,
  cat,
  init,
  isTrue,
  log,
  markSeen,
  nowSec,
  paused,
  policy,
  readFields,
  readLines,
  repoList,
  run,
  seen,
  seenPath,
  setupGhToken,
  words,
} from "./lib.ts";

// Turn ISO8601 in UTC into epoch seconds (what BSD `date -j -f` accepted).
function epoch(s: string): number | undefined {
  const m = /^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)Z$/.exec(s);
  if (!m) return undefined;
  const [y, mo, d, h, mi, se] = m.slice(1).map(Number);
  return Date.UTC(y, mo - 1, d, h, mi, se) / 1000;
}

// Each dispatched job is its own process, as before: it takes its own lock and its
// exit releases it.
async function dispatch(script: string, ...args: string[]): Promise<void> {
  const path = `${AGENT_DIR}/${script}`;
  log(`→ ${[path, ...args].join(" ")}`);
  if ((await run([process.execPath, path, ...args])).code !== 0) log(`WARN: failed: ${[path, ...args].join(" ")}`);
}

const hasLabel = (labels: string, name: string): boolean => `,${labels},`.includes(`,${name},`);

export async function main(): Promise<number> {
  init();
  if (paused()) return 0;
  if (!acquireLock("poller", 30)) {
    log("the previous poll is still running");
    return 0;
  }
  await setupGhToken();
  const NOW = nowSec();

  for (const repo of words(repoList().map((l) => `${l}\n`).join(""))) {
    if (policy(repo, "trigger", "both") === "actions") {
      log(`trigger=actions, the poller leaves this one alone: ${repo}`);
      continue;
    }

    // --- the first pass does nothing ------------------------------------
    // Starting cold would mean reacting to every open issue and every failed run at
    // once. The first pass only records what already exists; work starts with what
    // arrives after that.
    const bootFile = seenPath(`${repo}/bootstrap`);
    if (!existsSync(bootFile)) {
      log(`first pass, recording the current state only: ${repo}`);
      for (const n of words(
        await capture(["gh", "issue", "list", "--repo", repo, "--state", "open", "--limit", "100", "--json", "number", "-q", ".[].number"]),
      )) {
        markSeen(`${repo}/issue-${n}/${await capture(["gh", "issue", "view", n, "--repo", repo, "--json", "updatedAt", "-q", ".updatedAt"])}`);
      }
      for (const id of words(
        await capture([
          "gh",
          "run",
          "list",
          "--repo",
          repo,
          "--status",
          "failure",
          "--limit",
          "50",
          "--json",
          "databaseId",
          "-q",
          ".[].databaseId",
        ]),
      )) {
        markSeen(`${repo}/run-${id}`);
      }
      const prs = (await run(
        [
          "gh",
          "pr",
          "list",
          "--repo",
          repo,
          "--state",
          "open",
          "--limit",
          "100",
          "--json",
          "number,headRefOid",
          "-q",
          '.[] | "\\(.number) \\(.headRefOid)"',
        ],
        { stdout: "pipe", stderr: "ignore" },
      )).stdout;
      for (const line of readLines(prs)) {
        const [n, s] = readFields(line, 2);
        markSeen(`${repo}/pr-${n}/${s}`);
      }
      mkdirSync(dirname(bootFile), { recursive: true });
      writeFileSync(bootFile, `${NOW}\n`);
      continue;
    }
    const BOOT_AT = Number(cat(bootFile) ?? NOW);

    // --- issues ----------------------------------------------------------
    if (isTrue(policy(repo, "autofix_issues", "true"))) {
      const list = (await run(
        [
          "gh",
          "issue",
          "list",
          "--repo",
          repo,
          "--state",
          "open",
          "--limit",
          "30",
          "--json",
          "number,createdAt,updatedAt,labels",
          "-q",
          '.[] | [(.number|tostring), .createdAt, .updatedAt, ([.labels[].name]|join(","))] | @tsv',
        ],
        { stdout: "pipe", stderr: "ignore" },
      )).stdout;
      for (const line of readLines(list)) {
        const [n, created, updated, labels] = readFields(line, 4, "\t");
        if (n === "") continue;
        if (hasLabel(labels, "no-claude")) continue;
        if (seen(`${repo}/issue-${n}/${updated}`)) continue;

        let act = false;
        // explicitly asked for by a person
        if (hasLabel(labels, "claude-fix")) act = true;
        // opened after the first pass and not touched yet
        if (!act) {
          const c = epoch(created);
          if (c !== undefined && c > BOOT_AT) {
            if (!["claude-in-progress", "claude-done", "claude-failed", "claude-needs-info"].some((l) => hasLabel(labels, l))) {
              act = true;
            }
          }
        }
        // someone answered a question the bot asked (resume when the last comment is not the bot)
        if (!act && hasLabel(labels, "claude-needs-info")) {
          const last = await capture(["gh", "issue", "view", n, "--repo", repo, "--json", "comments", "-q", ".comments[-1].body"]);
          if (!last.includes(MARK) && last !== "") act = true;
        }

        if (act) await dispatch("run-autofix.ts", repo, `issue:${n}`);
      }
    }

    // --- failed Actions runs ---------------------------------------------
    if (isTrue(policy(repo, "autofix_ci", "true"))) {
      const list = (await run(
        [
          "gh",
          "run",
          "list",
          "--repo",
          repo,
          "--status",
          "failure",
          "--limit",
          "20",
          "--json",
          "databaseId,createdAt",
          "-q",
          ".[] | [(.databaseId|tostring), .createdAt] | @tsv",
        ],
        { stdout: "pipe", stderr: "ignore" },
      )).stdout;
      for (const line of readLines(list)) {
        const [id, created] = readFields(line, 2, "\t");
        if (id === "") continue;
        if (seen(`${repo}/run-${id}`)) continue;
        // do not dig up the backlog; only failures from the last twelve hours
        const c = epoch(created);
        if (c !== undefined && NOW - c > 43200) {
          markSeen(`${repo}/run-${id}`);
          continue;
        }
        await dispatch("run-autofix.ts", repo, `run:${id}`);
      }
    }

    // --- pull request review ---------------------------------------------
    if (isTrue(policy(repo, "review", "true"))) {
      const list = (await run(
        [
          "gh",
          "pr",
          "list",
          "--repo",
          repo,
          "--state",
          "open",
          "--limit",
          "30",
          "--json",
          "number,headRefOid,isDraft",
          "-q",
          ".[] | [(.number|tostring), .headRefOid, (.isDraft|tostring)] | @tsv",
        ],
        { stdout: "pipe", stderr: "ignore" },
      )).stdout;
      for (const line of readLines(list)) {
        const [n, s, draft] = readFields(line, 3, "\t");
        if (n === "") continue;
        if (draft === "true") continue;
        if (seen(`${repo}/pr-${n}/${s}`)) continue;
        await dispatch("run-review.ts", repo, n);
      }
    }
  }

  log("poll finished");
  return 0;
}

if (import.meta.main) process.exit(await main());
