#!/usr/bin/env bun
// Claude Code: the managed keys shipped to remotes (settings.remote.json) must equal what the
// workstation's settings.json actually holds ("the client terminal is the source of truth",
// configs/cli/claude/README.md). Shipping a key the workstation lacks creates "default on the
// workstation, explicit on remotes" drift; that happened on 2026-08-13, hence this check.
//
// The workstation file is a symlink into gapul/ai-agent-state, which is not in this repository.
// Where the link is dangling (CI checkout, a store copy) there is nothing to compare, so skip.
//
// Ported from scripts/check-claude-settings-drift.py.
import { existsSync, readFileSync, writeSync } from "node:fs";
import { join } from "node:path";

const out = (line: string): void => void writeSync(1, `${line}\n`);
const err = (line: string): void => void writeSync(2, `${line}\n`);

const CLAUDE = join(import.meta.dir, "..", "configs", "cli", "claude");

type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
type JsonObject = { [key: string]: Json };

const isObject = (v: Json | undefined): v is JsonObject =>
  typeof v === "object" && v !== null && !Array.isArray(v);

// Python's == on parsed JSON: deep, key order ignored, and True == 1 / False == 0.
function jsonEqual(a: Json, b: Json): boolean {
  if (typeof a === "boolean" && typeof b === "number") return Number(a) === b;
  if (typeof a === "number" && typeof b === "boolean") return a === Number(b);
  if (Array.isArray(a) || Array.isArray(b)) {
    if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) return false;
    return a.every((x, i) => jsonEqual(x, b[i]));
  }
  if (isObject(a) || isObject(b)) {
    if (!isObject(a) || !isObject(b)) return false;
    const keys = Object.keys(a);
    if (keys.length !== Object.keys(b).length) return false;
    return keys.every((k) => Object.hasOwn(b, k) && jsonEqual(a[k], b[k]));
  }
  return a === b;
}

// Walk the managed file's shape and collect leaf paths that differ on the workstation.
// Descend only when both sides are objects, the same promise merge-claude-settings.py's
// deep_merge makes (permissions manages only defaultMode; allow is left to each side).
function drift(managed: JsonObject, source: JsonObject, prefix = ""): string[] {
  const found: string[] = [];
  for (const [name, value] of Object.entries(managed)) {
    const path = prefix + name;
    if (name === "$schema") continue;
    if (!Object.hasOwn(source, name)) {
      found.push(`${path} (母艦の settings.json に無い)`);
      continue;
    }
    const current = source[name];
    if (isObject(value) && isObject(current)) found.push(...drift(value, current, `${path}.`));
    else if (!jsonEqual(value, current)) found.push(path);
  }
  return found;
}

function main(): number {
  const workstation = join(CLAUDE, "settings.json");
  if (!existsSync(workstation)) {
    out(`claude: ${workstation} が読めない (ai-agent-state が無い環境) のでスキップ`);
    return 0;
  }
  const managed = JSON.parse(readFileSync(join(CLAUDE, "settings.remote.json"), "utf8"));
  const drifted = drift(managed, JSON.parse(readFileSync(workstation, "utf8")));
  if (drifted.length > 0) {
    err("claude: settings.remote.json の管理キーが母艦の settings.json と食い違う:");
    for (const d of drifted) err(`  ${d}`);
    return 1;
  }
  out("claude: managed settings match the workstation");
  return 0;
}

function assertEqual(actual: string[], expected: string[]): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`demo: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

if (Bun.argv.slice(2).includes("--demo")) {
  assertEqual(drift({ a: 1, b: { c: 2 } }, { a: 1, b: { c: 2 } }), []);
  assertEqual(drift({ a: 1 }, {}), ["a (母艦の settings.json に無い)"]);
  assertEqual(drift({ b: { c: 2 } }, { b: { c: 3 } }), ["b.c"]);
  assertEqual(drift({ $schema: "x", b: { c: 2 } }, { b: 5 }), ["b"]);
  out("demo ok");
  process.exit(0);
}
process.exit(main());
