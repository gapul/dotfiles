#!/usr/bin/env bun
// Move the pins of the custom packages in nix/pkgs (slk, Unity CLI, the Fabric server and its
// mods, Geyser, the ArtCraft apps, Compositor) to their newest upstream releases. Run hourly by .github/workflows/
// update-flake-lock.yml, which opens a PR with whatever changed.
//
// Ported from update-custom-packages.sh. HTTP goes through fetch and hashes are computed
// in-process (the SRI strings are what `nix hash file` / `nix hash convert` printed), so the only
// external command left is `gh` for the GitHub release lookups, which carries the workflow's token.
import { readFileSync, writeFileSync, writeSync } from "node:fs";

const repo = `${import.meta.dir}/..`;
const slkFile = `${repo}/nix/pkgs/slk.nix`;
const unityFile = `${repo}/nix/pkgs/unity-cli.nix`;
const fabricFile = `${repo}/nix/pkgs/fabric-server.nix`;
const geyserFile = `${repo}/nix/pkgs/geyser.nix`;
const modsFile = `${repo}/nix/pkgs/fabric-mods.nix`;
const macminiFile = `${repo}/nix/hosts/macmini.nix`;
const craftAppsFile = `${repo}/nix/pkgs/artcraft-apps.nix`;
const artcraftFile = `${repo}/nix/pkgs/artcraft.nix`;
const compositorFile = `${repo}/nix/pkgs/compositor.nix`;
const protocolMapUrl =
  "https://raw.githubusercontent.com/PrismarineJS/minecraft-data/master/data/pc/common/protocolVersions.json";

const out = (line: string): void => void writeSync(1, `${line}\n`);
const err = (line: string): void => void writeSync(2, `${line}\n`);

class Fatal extends Error {}

async function get(url: string, timeoutMs?: number): Promise<Response> {
  const res = await fetch(url, timeoutMs ? { signal: AbortSignal.timeout(timeoutMs) } : undefined);
  if (!res.ok) throw new Fatal(`${url}: HTTP ${res.status}`);
  return res;
}
const getJson = async <T>(url: string, timeoutMs?: number): Promise<T> => (await get(url, timeoutMs)).json() as T;
const getBytes = async (url: string): Promise<Uint8Array> => new Uint8Array(await (await get(url)).arrayBuffer());

// SRI hashes, as `nix hash file --type sha256` and `nix hash convert --to sri` print them.
const sriSha256 = (data: Uint8Array): string =>
  `sha256-${new Bun.CryptoHasher("sha256").update(data).digest("base64")}`;
function sriFromHex(algo: "sha256" | "sha512", hex: unknown): string {
  const len = algo === "sha256" ? 64 : 128;
  if (typeof hex !== "string" || !new RegExp(`^[0-9a-fA-F]{${len}}$`).test(hex)) {
    throw new Fatal(`not a ${algo} hex digest: ${String(hex)}`);
  }
  return `${algo}-${Buffer.from(hex, "hex").toString("base64")}`;
}

// sed -n 's/^[[:space:]]*<key> = "\([^"]*\)";/\1/p' <file> | head -1
function pinned(file: string, key: string): string {
  const m = new RegExp(`^\\s*${key} = "([^"]*)";`, "m").exec(readFileSync(file, "utf8"));
  return m ? m[1] : "";
}

// Rewrite a file line by line, as the awk programs did. `edit` gets each line and returns it
// (possibly changed); state lives in the caller's closure.
function rewrite(file: string, edit: (line: string) => string): void {
  const text = readFileSync(file, "utf8");
  const lines = text.replace(/\n$/, "").split("\n");
  writeFileSync(file, `${lines.map(edit).join("\n")}\n`);
}

// awk's sub(/"[^"]+"/, "\"" value "\""): replace the first non-empty quoted string.
const setQuoted = (line: string, value: string): string => line.replace(/"[^"]+"/, () => `"${value}"`);

// `gh api <path>`, through gh so the GitHub API sees the workflow's token rather than the
// runner's shared anonymous rate limit.
function ghApi(path: string, jq?: string): string {
  const gh = Bun.spawnSync(["gh", "api", path, ...(jq ? ["--jq", jq] : [])], {
    stdin: "ignore",
    stdout: "pipe",
    stderr: "inherit",
  });
  // gh has already said what went wrong; exit with its code, like set -e did.
  if (gh.exitCode !== 0) process.exit(gh.exitCode ?? 1);
  return gh.stdout.toString().replace(/\n+$/, "");
}

interface GhRelease {
  tag_name: string;
  draft: boolean;
  prerelease: boolean;
  assets: { name: string; browser_download_url: string; digest?: string | null }[];
}

// SRI hashes of release assets without downloading them where possible: the release's
// SHA256SUMS.txt first, then the sha256 digest GitHub records per asset, and only then the
// asset itself.
async function releaseHashes(release: GhRelease, names: string[]): Promise<Record<string, string>> {
  const sums: Record<string, string> = {};
  const sumsAsset = release.assets.find((a) => a.name === "SHA256SUMS.txt");
  if (sumsAsset) {
    for (const line of (await (await get(sumsAsset.browser_download_url, 30_000)).text()).split("\n")) {
      const m = /^([0-9a-fA-F]{64})\s+\*?(\S+)$/.exec(line.trim());
      if (m) sums[m[2]] = m[1];
    }
  }
  const hashes: Record<string, string> = {};
  for (const name of names) {
    const asset = release.assets.find((a) => a.name === name);
    if (!asset) throw new Fatal(`${release.tag_name}: no asset ${name}`);
    const digest = asset.digest?.startsWith("sha256:") ? asset.digest.slice("sha256:".length) : undefined;
    const hex = sums[name] ?? digest;
    hashes[name] = hex ? sriFromHex("sha256", hex) : sriSha256(await getBytes(asset.browser_download_url));
  }
  return hashes;
}

const latestRelease = (repoPath: string): GhRelease =>
  JSON.parse(ghApi(`repos/${repoPath}/releases/latest`)) as GhRelease;

async function updateSlk(): Promise<void> {
  const pinnedSlk = pinned(slkFile, "version");
  const latestSlk = ghApi("repos/gammons/slk/releases/latest", '.tag_name | ltrimstr("v")');
  if (pinnedSlk === latestSlk) return;

  const hashes: Record<string, string> = {};
  for (const arch of ["arm64", "x86_64"]) {
    const url = `https://github.com/gammons/slk/releases/download/v${latestSlk}/slk_${latestSlk}_darwin_${arch}.tar.gz`;
    hashes[arch] = sriSha256(await getBytes(url));
  }
  let done = false;
  let platform = "";
  rewrite(slkFile, (line) => {
    if (/version = "/.test(line) && !done) {
      line = setQuoted(line, latestSlk);
      done = true;
    }
    if (/aarch64-darwin =/.test(line)) platform = "arm64";
    if (/x86_64-darwin =/.test(line)) platform = "x86_64";
    if (/hash = "/.test(line) && platform !== "") {
      line = setQuoted(line, hashes[platform]);
      platform = "";
    }
    return line;
  });
  out(`slk: ${pinnedSlk} -> ${latestSlk}`);
}

async function updateUnity(): Promise<void> {
  const manifest = await getJson<{ version: string; binaries: Record<string, { sha256?: string } | undefined> }>(
    "https://public-cdn.cloud.unity3d.com/hub/prod/cli/latest-beta.json",
  );
  const latestUnity = String(manifest.version);
  const pinnedUnity = pinned(unityFile, "version");
  if (pinnedUnity === latestUnity) return;

  const hashes: Record<string, string> = {};
  for (const platform of ["darwin-arm64", "darwin-x64", "linux-arm64", "linux-x64"]) {
    hashes[platform] = sriFromHex("sha256", manifest.binaries?.[platform]?.sha256);
  }
  let done = false;
  let hash = "";
  rewrite(unityFile, (line) => {
    if (/version = "/.test(line) && !done) {
      line = setQuoted(line, latestUnity);
      done = true;
    }
    for (const platform of Object.keys(hashes)) {
      if (line.includes(`platform = "${platform}"`)) hash = hashes[platform];
    }
    if (/hash = "/.test(line) && hash !== "") {
      line = setQuoted(line, hash);
      hash = "";
    }
    return line;
  });
  out(`unity-cli: ${pinnedUnity} -> ${latestUnity}`);
}

// --- Fabric (Minecraft servers) -------------------------------------------------------------
// 追うのは「宣言してある mod が全部揃っている、いちばん新しい安定版の MC バージョン」。
// 新しい版が出た直後は mod が追いつくまで数日〜数週間あり、その間は前の版に留まる。
// 同じ版の中でも loader と mod の新しいリリースは拾う。
// mod のハッシュは Modrinth が公開している sha512 をそのまま使う (jar を落とさない)。
// Fabric の起動 jar だけはハッシュが公開されていないので、落として計る。

interface ModPick {
  project: string;
  slug: string;
  optional: boolean;
  // Unset when an optional mod has no release for this game version yet.
  file?: { filename: string; url: string; sha512: string };
}

interface ModrinthVersion {
  version_type: string;
  files: { primary: boolean; filename: string; url: string; hashes: { sha512: string } }[];
}

// 揃う版が無ければ undefined。
async function pickFabric(): Promise<{ mc: string; loader: string; installer: string; mods: ModPick[] } | undefined> {
  const timeout = 30_000;
  const declared = [...readFileSync(modsFile, "utf8").matchAll(/^\s*# modrinth:(\S+) (\S+)( optional)?$/gm)].map(
    (m) => ({ project: m[1], slug: m[2], optional: m[3] !== undefined }),
  );
  const games = (await getJson<{ version: string; stable: boolean }[]>("https://meta.fabricmc.net/v2/versions/game", timeout))
    .filter((g) => g.stable)
    .map((g) => g.version);
  const installer = (await getJson<{ version: string }[]>("https://meta.fabricmc.net/v2/versions/installer", timeout))[0]
    .version;
  for (const mc of games) {
    const loaders = (
      await getJson<{ loader: { version: string; stable: boolean } }[]>(
        `https://meta.fabricmc.net/v2/versions/loader/${mc}`,
        timeout,
      )
    ).filter((l) => l.loader.stable);
    if (loaders.length === 0) continue;
    const picks: ModPick[] = [];
    let complete = true;
    for (const mod of declared) {
      const q = new URLSearchParams({ loaders: '["fabric"]', game_versions: `["${mc}"]` });
      const vs = await getJson<ModrinthVersion[]>(`https://api.modrinth.com/v2/project/${mod.project}/version?${q}`, timeout);
      if (vs.length === 0) {
        if (mod.optional) {
          picks.push(mod);
          continue;
        }
        complete = false;
        break;
      }
      // 正式版があればそれ、無ければ beta/alpha (Modrinth は新しい順に返す)。
      const v = vs.find((x) => x.version_type === "release") ?? vs[0];
      const f = v.files.find((x) => x.primary);
      if (!f) throw new Fatal(`${mod.project}: no primary file for ${mc}`);
      picks.push({ ...mod, file: { filename: f.filename, url: f.url, sha512: f.hashes.sha512 } });
    }
    if (complete) return { mc, loader: loaders[0].loader.version, installer, mods: picks };
  }
  return undefined;
}

async function updateFabric(): Promise<void> {
  const pinnedMc = pinned(fabricFile, "mcVersion");
  const pinnedLoader = pinned(fabricFile, "loader");
  const pinnedInstaller = pinned(fabricFile, "installer");

  const pick = await pickFabric();
  if (!pick) return;
  const { mc, loader, installer } = pick;

  if (pinnedMc !== mc || pinnedLoader !== loader || pinnedInstaller !== installer) {
    const fabricHash = sriSha256(
      await getBytes(`https://meta.fabricmc.net/v2/versions/loader/${mc}/${loader}/${installer}/server/jar`),
    );
    rewrite(fabricFile, (line) => {
      if (/^\s*mcVersion = "/.test(line)) line = setQuoted(line, mc);
      if (/^\s*loader = "/.test(line)) line = setQuoted(line, loader);
      if (/^\s*installer = "/.test(line)) line = setQuoted(line, installer);
      if (/^\s*hash = "/.test(line)) line = setQuoted(line, fabricHash);
      return line;
    });
    out(`fabric: ${pinnedMc}/${pinnedLoader}/${pinnedInstaller} -> ${mc}/${loader}/${installer}`);
  }

  // mod 一覧はヘッダ (= 最初の `[` まで) を残して丸ごと作り直す。
  const current = readFileSync(modsFile, "utf8");
  const lines = current.replace(/\n$/, "").split("\n");
  const open = lines.indexOf("[");
  let next = `${(open < 0 ? lines : lines.slice(0, open + 1)).join("\n")}\n`;
  for (const mod of pick.mods) {
    const marker = `  # modrinth:${mod.project} ${mod.slug}${mod.optional ? " optional" : ""}\n`;
    if (!mod.file) {
      // 任意の mod がこの版にまだ無い。行だけ残して、出た時に拾えるようにする。
      next += `${marker}  # (no release for ${mc} yet)\n`;
      continue;
    }
    const { filename, url, sha512 } = mod.file;
    next += `${marker}  (fetchurl {\n    name = "${filename}";\n    url = "${url}";\n    hash = "${sriFromHex("sha512", sha512)}";\n  })\n`;
  }
  next += "]\n";
  if (next !== current) {
    writeFileSync(modsFile, next);
    out(`fabric mods: 更新あり (${mc} 向け)`);
  }

  // サーバーが寝ている間の status は lazymc が代わりに返すので、そこに書く protocol も一緒に動かす。
  // 置き去りにすると、更新した翌朝からサーバー一覧に「非対応」の×が出る。番号は Fabric の API に
  // 無いので外から引く。出たばかりの版はまだ載っていないことがあり、その時は据え置く。
  if (pinnedMc !== mc) {
    const map = await getJson<{ minecraftVersion: string; version: number }[]>(protocolMapUrl, 30_000);
    const proto = map.find((e) => e.minecraftVersion === mc)?.version;
    if (proto !== undefined) {
      rewrite(macminiFile, (line) => (/^\s*mcProtocol = /.test(line) ? line.replace(/= [0-9]+/, `= ${proto}`) : line));
      out(`fabric (lazymc の表示): ${mc} / protocol ${proto}`);
    } else {
      err(`fabric: ${mc} の protocol 番号が引けなかったので lazymc の表示は据え置き`);
    }
  }
}

// --- Geyser (Bedrock の入口) -----------------------------------------------------------------
// 統合版はほぼ毎月更新され、Geyser はその数日後に追いつく。ビルドごとの sha256 を API が返すので
// 落とさずに pin を動かせる。Java 側の版とは独立 (Geyser は複数の Java 版を同時に相手にする)。
async function updateGeyser(): Promise<void> {
  const pinnedGeyser = pinned(geyserFile, "version");
  const pinnedBuild = pinned(geyserFile, "build");
  const d = await getJson<{ version: string; build: number; downloads: { standalone: { sha256: string } } }>(
    "https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest",
    30_000,
  );
  const gv = String(d.version);
  const gb = String(d.build);
  const gsha = String(d.downloads.standalone.sha256);
  if (pinnedGeyser === gv && pinnedBuild === gb) return;
  let v = false;
  let b = false;
  let s = false;
  rewrite(geyserFile, (line) => {
    if (/^\s*version = "/.test(line) && !v) {
      line = setQuoted(line, gv);
      v = true;
    }
    if (/^\s*build = "/.test(line) && !b) {
      line = setQuoted(line, gb);
      b = true;
    }
    if (/^\s*sha256 = "/.test(line) && !s) {
      line = setQuoted(line, gsha);
      s = true;
    }
    return line;
  });
  out(`geyser: ${pinnedGeyser}-${pinnedBuild} -> ${gv}-${gb}`);
}

// --- ArtCraft (storytold) and Compositor -----------------------------------------------------
// The twelve Craft apps share one release layout (github.com/storytold/<name>, tag v<version>,
// a universal dmg for darwin and an x86_64 tarball for Linux), so they are one list in
// artcraft-apps.nix; each entry's version, hash and linuxHash move together.
async function updateCraftApps(): Promise<void> {
  const text = readFileSync(craftAppsFile, "utf8");
  const apps = [...text.matchAll(/^\s*name = "([^"]+)";\n\s*version = "([^"]+)";/gm)].map((m) => ({
    name: m[1],
    pinned: m[2],
  }));
  const bumps: Record<string, { version: string; hash: string; linuxHash: string }> = {};
  for (const app of apps) {
    const pname = app.name.toLowerCase();
    const release = latestRelease(`storytold/${pname}`);
    const version = release.tag_name.replace(/^v/, "");
    if (version === app.pinned) continue;
    const dmg = `${pname}-${version}-macos-universal.dmg`;
    const tarball = `${pname}-${version}-linux-x86_64.tar.gz`;
    const hashes = await releaseHashes(release, [dmg, tarball]);
    bumps[app.name] = { version, hash: hashes[dmg], linuxHash: hashes[tarball] };
  }
  if (Object.keys(bumps).length === 0) return;

  let bump: (typeof bumps)[string] | undefined;
  rewrite(craftAppsFile, (line) => {
    const name = /^\s*name = "([^"]+)";/.exec(line);
    if (name) bump = bumps[name[1]];
    if (!bump) return line;
    if (/^\s*version = "/.test(line)) line = setQuoted(line, bump.version);
    if (/^\s*hash = "/.test(line)) line = setQuoted(line, bump.hash);
    if (/^\s*linuxHash = "/.test(line)) line = setQuoted(line, bump.linuxHash);
    return line;
  });
  for (const app of apps) {
    if (bumps[app.name]) out(`${app.name.toLowerCase()}: ${app.pinned} -> ${bumps[app.name].version}`);
  }
}

// A single-asset release: `version` and the src `hash` in a finalAttrs derivation whose url is
// `asset(version)` under the release tagged `tag(version)`.
async function updateReleaseAsset(
  label: string,
  file: string,
  repoPath: string,
  tag: (version: string) => string,
  asset: (version: string) => string,
): Promise<void> {
  const pinnedVersion = pinned(file, "version");
  // ArtCraft's tags carry a component prefix (artcraft-v...), so pick the newest release
  // with this line's prefix rather than trusting releases/latest.
  const releases = JSON.parse(ghApi(`repos/${repoPath}/releases?per_page=30`)) as GhRelease[];
  const prefix = tag("");
  const release = releases.find((r) => !r.draft && !r.prerelease && r.tag_name.startsWith(prefix));
  if (!release) throw new Fatal(`${repoPath}: no release tagged ${prefix}*`);
  const version = release.tag_name.slice(prefix.length);
  if (version === pinnedVersion) return;
  const hash = (await releaseHashes(release, [asset(version)]))[asset(version)];
  let v = false;
  let h = false;
  rewrite(file, (line) => {
    if (/^\s*version = "/.test(line) && !v) {
      line = setQuoted(line, version);
      v = true;
    }
    if (/^\s*hash = "/.test(line) && !h) {
      line = setQuoted(line, hash);
      h = true;
    }
    return line;
  });
  out(`${label}: ${pinnedVersion} -> ${version}`);
}

try {
  await updateSlk();
  await updateUnity();
  await updateFabric();
  await updateGeyser();
  await updateCraftApps();
  await updateReleaseAsset(
    "artcraft",
    artcraftFile,
    "storytold/artcraft",
    (v) => `artcraft-v${v}`,
    (v) => `ArtCraft_${v}_universal.dmg`,
  );
  await updateReleaseAsset("compositor", compositorFile, "robbietilton/Compositor", (v) => `v${v}`, () => "Compositor.dmg");
} catch (e) {
  err(`update-custom-packages: ${e instanceof Error ? e.message : String(e)}`);
  process.exit(1);
}
