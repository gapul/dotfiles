#!/usr/bin/env bun
// Write a markdown digest of the last week's activity in the IS-CPU-6 GitHub org.
//
// Runs as gapul (launchd agent, nix/home/macmini-soudan-digest.nix) because gapul's gh login is
// the only one with access to the org's private repos. The soudan bot's weekly-slides cron job
// reads the file it writes; the token itself never reaches hermes or the hsoudan sandbox.
//
// Usage: soudan-github-digest.ts OUTPUT [DAYS]
//
// Ported from soudan-github-digest.py; output is byte-for-byte the same.
import { renameSync, writeFileSync } from "node:fs";

const ORG = "IS-CPU-6";
const JST_OFFSET_MS = 9 * 3600 * 1000;

interface Commit {
  sha: string;
  author: { login?: string } | null;
  commit: { author: { name: string; date: string }; message: string };
}
interface Pull {
  number: number;
  state: string;
  merged_at: string | null;
  updated_at: string;
  title: string;
  user: { login: string };
  head: { ref: string };
  base: { ref: string };
}
interface Issue {
  number: number;
  state: string;
  title: string;
  user: { login: string };
  pull_request?: unknown;
}
interface Repo {
  name: string;
  archived?: boolean;
  pushed_at: string;
}

class CommandError extends Error {}

// `gh api --paginate --slurp` returns an array of pages; flatten them into one list.
function gh<T>(path: string): T[] {
  const cmd = ["gh", "api", "--paginate", "--slurp", path];
  const p = Bun.spawnSync(cmd, { stdin: "ignore", stdout: "pipe", stderr: "pipe" });
  if (p.exitCode !== 0) {
    throw new CommandError(`Command ${JSON.stringify(cmd)} returned non-zero exit status ${p.exitCode}.`);
  }
  const pages = JSON.parse(p.stdout.toString()) as unknown[];
  const items: T[] = [];
  for (const page of pages) items.push(...((Array.isArray(page) ? page : [page]) as T[]));
  return items;
}

const pad = (n: number): string => String(n).padStart(2, "0");

// Wall-clock fields of an instant in JST, read through the UTC getters of a shifted Date.
function jstParts(d: Date) {
  const j = new Date(d.getTime() + JST_OFFSET_MS);
  return {
    y: j.getUTCFullYear(),
    mo: pad(j.getUTCMonth() + 1),
    d: pad(j.getUTCDate()),
    h: pad(j.getUTCHours()),
    mi: pad(j.getUTCMinutes()),
  };
}

function jst(stamp: string): string {
  const p = jstParts(new Date(stamp));
  return `${p.mo}/${p.d} ${p.h}:${p.mi}`;
}

// Python's str.splitlines()[0][:160]: same line breaks, counted in code points.
function subject(message: string): string {
  const first = message.split(/\r\n|[\n\v\f\r\x1c\x1d\x1e\x85\u2028\u2029]/)[0] ?? "";
  return Array.from(first).slice(0, 160).join("");
}

// Python compares str by code point; for tuples, element by element.
function cmp(a: string, b: string): number {
  const x = Array.from(a, (c) => c.codePointAt(0) ?? 0);
  const y = Array.from(b, (c) => c.codePointAt(0) ?? 0);
  for (let i = 0; i < Math.min(x.length, y.length); i++) if (x[i] !== y[i]) return x[i] - y[i];
  return x.length - y.length;
}
function cmpTuple(a: string[], b: string[]): number {
  for (let i = 0; i < a.length; i++) {
    const c = cmp(a[i], b[i]);
    if (c !== 0) return c;
  }
  return 0;
}

function main(): void {
  const outPath = Bun.argv[2];
  if (outPath === undefined) {
    process.stderr.write("usage: soudan-github-digest.ts OUTPUT [DAYS]\n");
    process.exit(1);
  }
  const days = Bun.argv.length > 3 ? Number.parseInt(Bun.argv[3], 10) : 8;
  const since = new Date(Date.now() - days * 86400 * 1000);
  const sinceS = `${since.toISOString().slice(0, 19)}Z`;
  const s = jstParts(since);

  const lines = [`# GitHub ${ORG}: activity since ${s.y}-${s.mo}-${s.d} ${s.h}:${s.mi} JST`, ""];
  const repos = gh<Repo>(`orgs/${ORG}/repos?per_page=100`).sort((a, b) => cmp(a.name, b.name));
  for (const repo of repos) {
    const name = repo.name;
    if (repo.archived || repo.pushed_at < sinceS) continue;
    const section: string[] = [];

    // Commits on every branch, not just the default one: work lands on personal branches
    // (e.g. 261018_ashitani) and is merged later.
    const seen = new Map<string, string[]>();
    for (const br of gh<{ name: string }>(`repos/${ORG}/${name}/branches?per_page=100`)) {
      let commits: Commit[];
      try {
        commits = gh<Commit>(`repos/${ORG}/${name}/commits?sha=${br.name}&since=${sinceS}&per_page=100`);
      } catch (e) {
        if (e instanceof CommandError) continue;
        throw e;
      }
      for (const c of commits) {
        if (seen.has(c.sha)) continue;
        const author = c.author?.login || c.commit.author.name;
        seen.set(c.sha, [c.commit.author.date, br.name, author, subject(c.commit.message)]);
      }
    }
    if (seen.size > 0) {
      section.push(`### commits (${seen.size})`);
      for (const [date, branch, author, msg] of [...seen.values()].sort(cmpTuple)) {
        section.push(`- ${jst(date)} [${branch}] ${author}: ${msg}`);
      }
    }

    const prs = gh<Pull>(`repos/${ORG}/${name}/pulls?state=all&sort=updated&direction=desc&per_page=50`).filter(
      (p) => p.updated_at >= sinceS,
    );
    if (prs.length > 0) {
      section.push("### pull requests");
      for (const p of prs) {
        const state = p.merged_at ? "merged" : p.state;
        section.push(`- #${p.number} ${state} ${p.user.login}: ${p.title} (${p.head.ref} -> ${p.base.ref})`);
      }
    }

    const issues = gh<Issue>(`repos/${ORG}/${name}/issues?state=all&since=${sinceS}&per_page=50`).filter(
      (i) => !("pull_request" in i),
    );
    if (issues.length > 0) {
      section.push("### issues");
      for (const i of issues) section.push(`- #${i.number} ${i.state} ${i.user.login}: ${i.title}`);
    }

    if (section.length > 0) {
      lines.push(`## ${name}`, ...section, "");
    }
  }

  const tmp = `${outPath}.tmp`;
  writeFileSync(tmp, `${lines.join("\n")}\n`);
  renameSync(tmp, outPath);
}

main();
