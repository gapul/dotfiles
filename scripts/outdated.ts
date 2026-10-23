#!/usr/bin/env bun
// `just outdated`: list what can be updated before running `just upgrade` (Homebrew, Xcode and
// the flake inputs' lock dates). Read-only.
//
// Ported from the inline bash + jq of the recipe; the output is the same. The jq-missing branch
// is gone with jq.
import { writeSync } from "node:fs";
import { join } from "node:path";

const flake = join(import.meta.dir, "..", "nix");

const out = (line: string): void => void writeSync(1, `${line}\n`);

// stdout of a command whose stderr went to /dev/null; "" when it is not installed.
function capture(cmd: string[]): string {
  if (!Bun.which(cmd[0])) return "";
  const p = Bun.spawnSync(cmd, { stdin: "inherit", stdout: "pipe", stderr: "ignore" });
  return p.stdout.toString();
}

// $(...) drops trailing newlines
const chomp = (s: string): string => s.replace(/\n+$/, "");

// `paste -sd', ' -`: join the lines, cycling through the delimiters "," and " ".
function pasteSerial(text: string, delims: string[]): string {
  if (text === "") return "";
  const lines = text.replace(/\n$/, "").split("\n");
  return lines.reduce((acc, line, i) => (i === 0 ? line : acc + delims[(i - 1) % delims.length] + line), "");
}

if (process.platform === "darwin") {
  out("━━━ Homebrew (formula + cask, --greedy) ━━━");
  const o = chomp(capture(["brew", "outdated", "--greedy"]));
  out(o !== "" ? o : "  (up to date)");
  out("");
  out("━━━ Xcode (xcodes) ━━━");
  if (Bun.which("xcodes")) {
    // auth-free preview: show what's installed. `xcodes update` (Apple login + maybe 2FA)
    // is intentionally left to `just upgrade` so this stays non-interactive.
    const inst = chomp(pasteSerial(capture(["xcodes", "installed"]).replace(/ +/g, " "), [",", " "]));
    out(`  installed: ${inst || "none"}   (just upgrade -> xcodes install --latest)`);
  } else {
    out("  (xcodes not installed)");
  }
  out("");
}

out("━━━ flake inputs (lock last-modified) ━━━");
interface LockNode {
  locked?: { lastModified?: number | null };
}
let nodes: Record<string, LockNode> = {};
try {
  nodes = (JSON.parse(capture(["nix", "flake", "metadata", flake, "--json"])) as { locks: { nodes: Record<string, LockNode> } }).locks.nodes;
} catch {
  // nix failed or printed nothing: the section stays empty, as it did with jq
}
const rows: { day: string; line: string }[] = [];
for (const [name, node] of Object.entries(nodes)) {
  const lm = node.locked?.lastModified;
  if (lm === undefined || lm === null) continue;
  // jq's strftime("%Y-%m-%d") is UTC
  const day = new Date(lm * 1000).toISOString().slice(0, 10);
  rows.push({ day, line: `  ${name.padEnd(22)} ${day}` });
}
// `sort -b -k2`: by date, ties by the whole line
const cmp = (a: string, b: string): number => (a < b ? -1 : a > b ? 1 : 0);
rows.sort((a, b) => cmp(a.day, b.day) || cmp(a.line, b.line));
for (const r of rows) out(r.line);
out("");
out("-> Update: just upgrade (all) / just update <input> (individual)");
