#!/usr/bin/env bun
// Pin Win11Debloat and WinUtil in upstream.psd1 to their latest GitHub releases.
// Runs on macOS or Linux (needs gh and bun). Review the diff before committing:
// a new WinUtil can rename tweak IDs (winutil-config.json) and a new Win11Debloat can
// drop arguments (win11debloat-args.txt); check-upstream.ts verifies both.
//
// Ported from update-upstream.sh. GitHub API calls still go through `gh` (it carries the
// token); downloads and hashes are done in-process.
import { readFileSync, renameSync, writeFileSync } from "node:fs";
import { dir, download, err, out, psd1, sha256 } from "./upstream.ts";

// `gh api <path> -q <jq>`; exit with gh's code if it fails, like set -e.
function gh(path: string, jq: string): string {
  const p = Bun.spawnSync(["gh", "api", path, "-q", jq], { stdin: "ignore", stdout: "pipe", stderr: "inherit" });
  if (p.exitCode !== 0) process.exit(p.exitCode ?? 1);
  return p.stdout.toString().replace(/\n+$/, "");
}

async function fetchOrDie(url: string): Promise<Uint8Array> {
  try {
    return await download(url);
  } catch (e) {
    err(e instanceof Error ? e.message : String(e));
    process.exit(1);
  }
}

const wTag = gh("repos/Raphire/Win11Debloat/releases/latest", ".tag_name");
const wCommit = gh(`repos/Raphire/Win11Debloat/commits/${wTag}`, ".sha");
const wUrl = `https://github.com/Raphire/Win11Debloat/archive/${wCommit}.zip`;
const wSha = sha256(await fetchOrDie(wUrl));

const uTag = gh("repos/ChrisTitusTech/winutil/releases/latest", ".tag_name");
const uUrl = `https://github.com/ChrisTitusTech/winutil/releases/download/${uTag}/winutil.ps1`;
const uSha = sha256(await fetchOrDie(uUrl));
// GitHub records a digest for release assets; refuse a download that does not match it
const uDigest = gh("repos/ChrisTitusTech/winutil/releases/latest", '.assets[] | select(.name == "winutil.ps1") | .digest');
if (uDigest !== `sha256:${uSha}`) {
  err(`winutil.ps1: downloaded ${uSha}, GitHub says ${uDigest}`);
  process.exit(1);
}

// Keep the header comment, regenerate the data
const lines = readFileSync(psd1, "utf8").split("\n");
const dataStart = lines.findIndex((l) => l.startsWith("@{"));
const header = (dataStart < 0 ? lines : lines.slice(0, dataStart)).join("\n").replaceAll("\r", "").replace(/\n+$/, "");
const body = `@{
    Win11Debloat = @{
        Version = '${wTag}'
        Commit  = '${wCommit}'
        Url     = '${wUrl}'
        Sha256  = '${wSha}'
    }
    WinUtil = @{
        Version = '${uTag}'
        Url     = '${uUrl}'
        Sha256  = '${uSha}'
    }
}
`;
writeFileSync(`${psd1}.new`, `${header}\n${body}`);
renameSync(`${psd1}.new`, psd1);

out(`Win11Debloat ${wTag} (${wCommit}), WinUtil ${uTag}`);
const check = Bun.spawnSync([process.execPath, `${dir}/check-upstream.ts`], {
  stdin: "inherit",
  stdout: "inherit",
  stderr: "inherit",
});
process.exit(check.exitCode ?? 1);
