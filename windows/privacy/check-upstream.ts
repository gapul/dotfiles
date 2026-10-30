#!/usr/bin/env bun
// Check that the declarations still match the pinned upstream scripts in upstream.psd1:
// - both downloads match their SHA256
// - every argument in win11debloat-args.txt is a parameter of that Win11Debloat.ps1
// - every ID in winutil-config.json is a tweak, toggle or feature that WinUtil knows
// WinUtil's headless run refuses an unknown ID, and Win11Debloat refuses an unknown
// argument, so a stale declaration fails the whole apply. Catch it here instead.
//
// Ported from check-upstream.sh. Downloads and hashes are done in-process; the Win11Debloat
// archive is still unpacked with `unzip`.
import { mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dir, download, err, field, out, sha256 } from "./upstream.ts";

const tmp = mkdtempSync(`${tmpdir()}/check-upstream.`);
let fail = 0;

async function fetchPinned(name: string, url: string, pinned: string): Promise<Uint8Array | undefined> {
  let data: Uint8Array;
  try {
    data = await download(url);
  } catch (e) {
    err(`FAIL ${name}: download failed: ${e instanceof Error ? e.message : e}`);
    fail = 1;
    return undefined;
  }
  const got = sha256(data);
  if (got !== pinned) {
    err(`FAIL ${name}: sha256 ${got}, pinned ${pinned}`);
    fail = 1;
    return undefined;
  }
  out(`OK   ${name}: sha256 matches`);
  return data;
}

// find <dir> -maxdepth 2 -name Win11Debloat.ps1 | head -1
function findScript(root: string): string | undefined {
  const entries = readdirSync(root, { withFileTypes: true });
  for (const e of entries) if (e.isFile() && e.name === "Win11Debloat.ps1") return `${root}/${e.name}`;
  for (const e of entries) {
    if (!e.isDirectory()) continue;
    if (readdirSync(`${root}/${e.name}`).includes("Win11Debloat.ps1")) return `${root}/${e.name}/Win11Debloat.ps1`;
  }
  return undefined;
}

async function checkWin11Debloat(): Promise<void> {
  const zip = await fetchPinned("Win11Debloat", field("Win11Debloat", "Url"), field("Win11Debloat", "Sha256"));
  if (!zip) return;
  writeFileSync(`${tmp}/w11d.zip`, zip);
  const unzip = Bun.spawnSync(["unzip", "-q", `${tmp}/w11d.zip`, "-d", `${tmp}/w11d`], {
    stdout: "inherit",
    stderr: "inherit",
  });
  if (unzip.exitCode !== 0) {
    rmSync(tmp, { recursive: true, force: true });
    process.exit(unzip.exitCode ?? 1);
  }
  const script = findScript(`${tmp}/w11d`);
  if (!script) throw new Error("Win11Debloat.ps1 not found in the archive");

  // The param() block runs from the top of the file to the first line that is just ")"
  const lines = readFileSync(script, "utf8").split("\n");
  const end = lines.findIndex((l) => l.startsWith(")"));
  const block = lines.slice(0, end < 0 ? lines.length : end + 1).join("\n");
  const params = new Set([...block.matchAll(/\$([A-Za-z0-9]*)/g)].map((m) => m[1]));

  const args = readFileSync(`${dir}/win11debloat-args.txt`, "utf8")
    .split("\n")
    .map((l) => l.replace(/\r$/, "").replace(/#.*/, "").trim())
    .filter((l) => l !== "");
  for (const arg of args) {
    const name = arg.replace(/^-/, "");
    if (params.has(name)) {
      out(`OK   Win11Debloat -${name}`);
    } else {
      err(`FAIL Win11Debloat -${name}: not a parameter of ${field("Win11Debloat", "Version")}`);
      fail = 1;
    }
  }
}

async function checkWinUtil(): Promise<void> {
  const data = await fetchPinned("WinUtil", field("WinUtil", "Url"), field("WinUtil", "Sha256"));
  if (!data) return;
  const script = new TextDecoder().decode(data);
  const config = readFileSync(`${dir}/winutil-config.json`, "utf8");
  for (const [, id] of config.matchAll(/"(WPF[A-Za-z0-9]*)"/g)) {
    if (script.includes(`"${id}": {`)) {
      out(`OK   WinUtil ${id}`);
    } else {
      err(`FAIL WinUtil ${id}: unknown to ${field("WinUtil", "Version")}`);
      fail = 1;
    }
  }
}

try {
  await checkWin11Debloat();
  await checkWinUtil();
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
process.exit(fail);
