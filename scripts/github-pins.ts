#!/usr/bin/env bun
// Update the GitHub pins nothing else updates, then stage what changed. Run by `just upgrade`.
//
// flake.lock covers the flake inputs and nixpkgs covers what it packages, but a handful of
// things are pinned by hand: two yazi packages that are not in nixpkgs, the Rosé Pine
// tmThemes, and prh's dictionary. They used to be vendored files that `just maintain` never
// touched either, so this is not a new chore — it is the same chore, now with a hash to check.
//
// The pins it edits are committed, so whichever machine runs it updates them for all of them.
//
// Ported from the inline bash + sed + jq of the github-pins recipe; output and exit code (always
// 0) are the same. The rewrites no longer need BSD `sed -i ""`.
import { readFileSync, writeFileSync, writeSync } from "node:fs";
import { join } from "node:path";

const dir = join(import.meta.dir, "..");

const out = (line: string): void => void writeSync(1, `${line}\n`);
const err = (line: string): void => void writeSync(2, `${line}\n`);

// stdout of a command whose stderr is discarded, or null when it fails.
function capture(cmd: string[]): string | null {
  const p = Bun.spawnSync(cmd, { stdin: "inherit", stdout: "pipe", stderr: "ignore" });
  return p.exitCode === 0 ? p.stdout.toString().replace(/\n+$/, "") : null;
}

const latestCommit = (repo: string): string | null =>
  capture(["gh", "api", `repos/${repo}/commits?per_page=1`, "--jq", ".[0].sha"]);

// `nix store prefetch-file --json … | jq -r .hash`, null when either fails.
function prefetch(args: string[]): string | null {
  const json = capture(["nix", "store", "prefetch-file", "--json", ...args]);
  if (json === null) return null;
  try {
    const hash = (JSON.parse(json) as { hash?: unknown }).hash;
    return typeof hash === "string" ? hash : JSON.stringify(hash ?? null);
  } catch {
    return null;
  }
}

const revert = (file: string): void =>
  void Bun.spawnSync(["git", "-C", dir, "checkout", "--", file], { stdout: "inherit", stderr: "inherit" });

// sed's `/addr/{n;s/…/…/;n;s/…/…/;}`: on a line matching addr, apply each edit to the next
// lines in turn.
function editAfter(text: string, addr: RegExp, edits: ((line: string) => string)[]): string {
  const lines = text.split("\n");
  for (let i = 0; i < lines.length; i++) {
    if (!addr.test(lines[i])) continue;
    for (const edit of edits) {
      if (i + 1 >= lines.length) break;
      i++;
      lines[i] = edit(lines[i]);
    }
  }
  return lines.join("\n");
}

const changed: string[] = [];

// file | repo | the line rev/hash follow
const tarballs: [string, string, string][] = [
  ["nix/modules/home/cli.nix", "h-hg/yamb.yazi", 'repo = "yamb.yazi";'],
  ["nix/modules/home/cli.nix", "Mintass/rose-pine.yazi", 'repo = "rose-pine.yazi";'],
  ["nix/lib/rose-pine-tm-theme.nix", "rose-pine/tm-theme", 'repo = "tm-theme";'],
];

for (const [rel, repo, anchor] of tarballs) {
  const file = join(dir, rel);
  // An unreachable API is a skip, not a failure — same as the font: this runs inside
  // `just maintain`, and a pin being a week old is not worth aborting an upgrade over.
  const sha = latestCommit(repo);
  if (sha === null) {
    err(`– ${repo}: commit lookup failed (offline?); skipped`);
    continue;
  }
  // The rev on the anchor line or the one after it (`grep -A1 -F anchor | sed -n 's/…rev = "…"/…/p'`).
  // A missing file reads as no rev, which the prefix check below skips.
  let lines: string[];
  try {
    lines = readFileSync(file, "utf8").split("\n");
  } catch {
    err(`grep: ${file}: No such file or directory`);
    continue;
  }
  const revs: string[] = [];
  for (let i = 0; i < lines.length; i++) {
    const near = lines[i].includes(anchor) || (i > 0 && lines[i - 1].includes(anchor));
    const m = near ? lines[i].match(/.*rev = "([^"]*)".*/) : null;
    if (m) revs.push(m[1]);
  }
  const cur = revs.join("\n");
  // The pins were written short; a short rev is a prefix of the long one it names.
  if (sha.startsWith(cur)) continue;
  const hash = prefetch(["--unpack", `https://github.com/${repo}/archive/${sha}.tar.gz`]);
  if (hash === null) {
    err(`– ${repo}: prefetch failed; skipped`);
    continue;
  }
  const text = editAfter(readFileSync(file, "utf8"), new RegExp(anchor), [
    (l) => l.replace(/rev = "[^"]*"/, () => `rev = "${sha}"`),
    (l) => l.replace(/hash = "[^"]*"/, () => `hash = "${hash}"`),
  ]);
  writeFileSync(file, text);
  // A rewritten rev with a stale hash is the quiet failure here: a fixed-output derivation is
  // keyed by its hash, so nix would hand out the old contents and never fetch the new ones.
  if (!text.includes(sha) || !text.includes(hash)) {
    err(`– ${repo}: rewrite did not take; leaving the pin alone`);
    revert(file);
    continue;
  }
  out(`${repo}: ${cur || "?"} -> ${sha.slice(0, 7)}`);
  changed.push(file);
}

// prh's dictionary is a single file, pinned by the commit in its URL.
{
  const file = join(dir, "nix/home/workstation.nix");
  const sha = latestCommit("prh/rules");
  if (sha !== null) {
    const cur = readFileSync(file, "utf8")
      .split("\n")
      .flatMap((l) => l.match(/.*raw.githubusercontent.com\/prh\/rules\/([0-9a-f]*)\/.*/)?.[1] ?? [])
      .join("\n");
    if (sha !== cur) {
      const hash = prefetch([`https://raw.githubusercontent.com/prh/rules/${sha}/media/WEB%2BDB_PRESS.yml`]);
      if (hash !== null) {
        let text = readFileSync(file, "utf8")
          .split("\n")
          .map((l) => l.replace(/(raw.githubusercontent.com\/prh\/rules\/)[0-9a-f]+/, (_, p: string) => p + sha))
          .join("\n");
        text = editAfter(text, /raw.githubusercontent.com\/prh\/rules/, [
          (l) => l.replace(/hash = "[^"]*"/, () => `hash = "${hash}"`),
        ]);
        writeFileSync(file, text);
        if (text.includes(sha) && text.includes(hash)) {
          // Often only the commit moves: the dictionary is one file in a repository of them.
          out(`prh/rules: ${cur.slice(0, 7)} -> ${sha.slice(0, 7)}`);
          changed.push(file);
        } else {
          err("– prh/rules: rewrite did not take; leaving the pin alone");
          revert(file);
        }
      }
    }
  } else {
    err("– prh/rules: commit lookup failed (offline?); skipped");
  }
}

if (changed.length > 0) {
  Bun.spawnSync(["git", "-C", dir, "add", ...changed], { stdout: "inherit", stderr: "inherit" });
  out("Updated pins. Apply with: just rebuild (automatic when run via upgrade)");
}
