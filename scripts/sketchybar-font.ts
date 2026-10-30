#!/usr/bin/env bun
// Update the sketchybar-app-font pin (version, URL and hash in nix/hosts/darwin.nix) and the
// icon_map.sh that ships with the same release, then stage both. Run by `just upgrade`.
//
// Ported from the inline bash + awk + sed of the sketchybar-font recipe; output and exit codes
// are the same. The rewrites no longer need BSD `sed -i ""`.
import { chmodSync, readFileSync, renameSync, statSync, writeFileSync, writeSync } from "node:fs";
import { join } from "node:path";

const repo = "kvndrsslr/sketchybar-app-font";
const dir = join(import.meta.dir, "..");
const map = join(dir, "configs/wm/sketchybar/plugins/icon_map.sh");
const darwinNix = join(dir, "nix/hosts/darwin.nix");

const out = (line: string): void => void writeSync(1, `${line}\n`);
const err = (line: string): void => void writeSync(2, `${line}\n`);

// stderr goes to the terminal; stdout is captured when asked for. Exits like `set -e` on failure
// unless `check` is off.
function run(cmd: string[], opts: { capture?: boolean; check?: boolean } = {}): { code: number; stdout: string } {
  const p = Bun.spawnSync(cmd, { stdin: "inherit", stdout: opts.capture ? "pipe" : "inherit", stderr: "inherit" });
  const code = p.exitCode ?? 1;
  if (code !== 0 && opts.check !== false) process.exit(code);
  return { code, stdout: opts.capture ? (p.stdout?.toString() ?? "") : "" };
}

const chomp = (s: string): string => s.replace(/\n+$/, "");

// sed's `/addr/{n;s/…/…/;}`: on each line matching addr, edit the line after it.
function editNextLine(text: string, addr: RegExp, edit: (line: string) => string): string {
  const lines = text.split("\n");
  for (let i = 0; i < lines.length - 1; i++) {
    if (addr.test(lines[i])) {
      lines[i + 1] = edit(lines[i + 1]);
      i++;
    }
  }
  return lines.join("\n");
}

// A transient network failure here used to abort `just maintain` entirely and roll back
// flake.lock. The font is a nice-to-have, so treat an unreachable API as "skip", like xcodes.
const view = run(["gh", "release", "view", "--repo", repo, "--json", "tagName", "-q", ".tagName"], {
  capture: true,
  check: false,
});
if (view.code !== 0) {
  err("– sketchybar-app-font: release lookup failed (offline?); skipped");
  process.exit(0);
}
const tag = chomp(view.stdout);

// The version on the line after the pname, as the first run of digits and dots.
let cur = "";
{
  const lines = readFileSync(darwinNix, "utf8").split("\n");
  const i = lines.findIndex((l) => l.includes('pname = "sketchybar-app-font"'));
  if (i >= 0 && i + 1 < lines.length) cur = lines[i + 1].match(/[0-9][0-9.]*/)?.[0] ?? "";
}
if (tag === `v${cur}`) process.exit(0);

out(`sketchybar-app-font: updating ${cur} -> ${tag}`);
run(["gh", "release", "download", tag, "--repo", repo, "--pattern", "icon_map.sh", "--output", map, "--clobber"]);
// Make the downloaded map callable: after the end marker, call the lookup, source the local
// overrides, and print the result.
{
  const lines = readFileSync(map, "utf8").split("\n");
  if (lines[lines.length - 1] === "") lines.pop();
  const kept: string[] = [];
  for (const line of lines) {
    kept.push(line);
    if (line.startsWith("### END-OF-ICON-MAP")) {
      kept.push(
        '__icon_map "$1"',
        '[ -r "${BASH_SOURCE%/*}/icon_map_local.sh" ] && source "${BASH_SOURCE%/*}/icon_map_local.sh"',
        'echo "$icon_result"',
      );
      break;
    }
  }
  writeFileSync(`${map}.tmp`, kept.length > 0 ? `${kept.join("\n")}\n` : "");
  renameSync(`${map}.tmp`, map);
}
// gh release assets are non-executable, so restore +x; plugins run icon_map.sh
// directly ($(...)), and without +x it fails with "permission denied" -> the
// workspace app icons silently vanish. `chmod` before `git add` so the staged
// mode is recorded as 100755 too.
// (`chmod +x`: add the execute bits the umask allows)
chmodSync(map, statSync(map).mode | (0o111 & ~process.umask()));
// The font itself is fetched by nix, so what gets updated here is the pin: version, URL,
// and hash. Prefetching is what produces the hash — a wrong one fails the build, loudly.
const prefetch = run(
  ["nix", "store", "prefetch-file", "--json", `https://github.com/${repo}/releases/download/${tag}/sketchybar-app-font.ttf`],
  { capture: true },
);
const hash = String((JSON.parse(prefetch.stdout) as { hash?: string }).hash ?? "null");
let nix = readFileSync(darwinNix, "utf8");
nix = editNextLine(nix, /pname = "sketchybar-app-font"/, (l) =>
  l.replace(/version = "[0-9.]+"/, () => `version = "${tag.replace(/^v/, "")}"`),
);
nix = nix
  .split("\n")
  .map((l) => l.replace(/(sketchybar-app-font\/releases\/download\/)v[0-9.]+/, (_, p: string) => p + tag))
  .join("\n");
nix = editNextLine(nix, /sketchybar-app-font\/releases\/download/, (l) =>
  l.replace(/hash = "[^"]*"/, () => `hash = "${hash}"`),
);
writeFileSync(darwinNix, nix);
run(["git", "-C", dir, "add", map, darwinNix]);
out(`Updated (${tag}). Apply with: just rebuild (automatic when run via upgrade)`);
