#!/usr/bin/env bun
// `just plist-sync`: pull GUI-side preference changes back into the repo (live -> dotfiles).
//
// darwin-apps.nix imports these plists wholesale on activation, so anything changed in an app's
// own UI is silently reverted by the next rebuild unless it is captured here.
// Only keys the repo file already tracks are updated: these apps also store volatile state
// (window frames, status item positions, color panel geometry) that would add churn on every run.
// To start tracking a new key, add it to the repo plist once (`plutil -insert`), then this picks it up.
//
// Ported from the inline bash + jq of the recipe; output and exit codes are the same. Values are
// compared and printed as compact JSON, as `jq -c` did, numbers spelled as plutil wrote them
// (jq keeps plain number literals, so 64-bit integers and long reals survive the round trip;
// exponent forms such as 1e+20, which jq would respell, are printed as plutil wrote them).
import { statSync, writeSync } from "node:fs";
import { join } from "node:path";

const dir = join(import.meta.dir, "..");

const out = (line: string): void => void writeSync(1, `${line}\n`);

// Like `set -e`: a failing command ends the script with its exit code.
function run(cmd: string[], opts: { stdin?: Uint8Array; capture?: boolean; quiet?: boolean; check?: boolean } = {}) {
  const p = Bun.spawnSync(cmd, {
    stdin: opts.stdin ?? "ignore",
    stdout: opts.capture ? "pipe" : "inherit",
    stderr: opts.quiet ? "ignore" : "inherit",
  });
  const code = p.exitCode ?? 1;
  if (code !== 0 && opts.check !== false) process.exit(code);
  return { code, stdout: p.stdout ?? new Uint8Array() };
}

// A number kept as its literal text from the JSON source.
class Num {
  constructor(readonly text: string) {}
}

type Json = null | boolean | string | Num | Json[] | { [k: string]: Json };

const parse = (text: string): Json =>
  JSON.parse(text, (_k, v: unknown, ctx?: { source?: string }) =>
    typeof v === "number" ? new Num(ctx?.source ?? String(v)) : v,
  ) as Json;

// `jq -c`
function compact(v: Json): string {
  if (v instanceof Num) return v.text;
  if (Array.isArray(v)) return `[${v.map(compact).join(",")}]`;
  if (v !== null && typeof v === "object")
    return `{${Object.entries(v)
      .map(([k, x]) => `${JSON.stringify(k)}:${compact(x)}`)
      .join(",")}}`;
  return JSON.stringify(v);
}

// Same set darwin-apps.nix imports. Add a line here when an import is added there.
const pairs: [string, string][] = [
  ["org.p0deje.Maccy", "configs/clipboard/maccy/Maccy.plist"],
  ["net.mtgto.inputmethod.macSKK", "configs/ime/skk/macSKK.plist"],
  ["io.github.gitusp.azoo-key-skkserv", "configs/ime/skk/azoo-key-skkserv.plist"],
];

// `defaults export <domain> - | plutil -convert json -o - -`, null when either step fails.
function livePrefs(domain: string): Record<string, Json> | null {
  const exported = run(["defaults", "export", domain, "-"], { capture: true, quiet: true, check: false });
  if (exported.code !== 0) return null;
  const json = run(["plutil", "-convert", "json", "-o", "-", "-"], {
    stdin: exported.stdout,
    capture: true,
    quiet: true,
    check: false,
  });
  if (json.code !== 0) return null;
  const text = new TextDecoder().decode(json.stdout);
  if (text.trim() === "") return null;
  return parse(text) as Record<string, Json>;
}

let changed = false;
for (const [domain, rel] of pairs) {
  const repo = join(dir, rel);
  if (!statSync(repo, { throwIfNoEntry: false })?.isFile()) {
    out(`– ${rel}: not in repo, skipped`);
    continue;
  }
  const live = livePrefs(domain);
  // An app that was never launched (or a sandbox not yet created) exports an empty dict.
  // Overwriting from that would quietly wipe the tracked settings, so skip instead.
  if (live === null || Object.keys(live).length === 0) {
    out(`– ${domain}: no live prefs, skipped`);
    continue;
  }
  const old = parse(
    new TextDecoder().decode(run(["plutil", "-convert", "json", "-o", "-", repo], { capture: true }).stdout),
  ) as Record<string, Json>;
  // jq's `keys` order: sorted by code point
  for (const key of Object.keys(old).sort((a, b) => (a < b ? -1 : a > b ? 1 : 0))) {
    const lv = compact(Object.hasOwn(live, key) ? live[key] : null);
    const rv = compact(old[key]);
    if (lv === "null") continue; // dropped on the live side: keep the tracked value
    if (lv === rv) continue;
    run(["plutil", "-replace", key, "-json", lv, repo]);
    out(`  ${rel}  ${key}: ${rv} -> ${lv}`);
    changed = true;
  }
}
if (!changed) {
  out("✓ tracked plist keys already match the live prefs");
} else {
  run(["git", "-C", dir, "--no-pager", "diff", "--stat", "--", "configs"]);
  out("Review the diff, then commit on a branch as usual.");
}
