#!/usr/bin/env bun
// Move the pins of the custom packages in nix/pkgs (slk, Unity CLI, the Fabric server and its
// mods, Geyser), and of the KernelSU modules in mobile/android/devices/*/root/sources.json, to
// their newest upstream releases. Run hourly by .github/workflows/
// update-flake-lock.yml, which opens a PR with whatever changed.
//
// Ported from update-custom-packages.sh. HTTP goes through fetch and hashes are computed
// in-process (the SRI strings are what `nix hash file` / `nix hash convert` printed), so the only
// external command left is `gh` for the slk release, which carries the workflow's token.
import { existsSync, readdirSync, readFileSync, writeFileSync, writeSync } from "node:fs";

const repo = `${import.meta.dir}/..`;
const slkFile = `${repo}/nix/pkgs/slk.nix`;
const unityFile = `${repo}/nix/pkgs/unity-cli.nix`;
const fabricFile = `${repo}/nix/pkgs/fabric-server.nix`;
const geyserFile = `${repo}/nix/pkgs/geyser.nix`;
const modsFile = `${repo}/nix/pkgs/fabric-mods.nix`;
const macminiFile = `${repo}/nix/hosts/macmini.nix`;
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

async function updateSlk(): Promise<void> {
  const pinnedSlk = pinned(slkFile, "version");
  const gh = Bun.spawnSync(["gh", "api", "repos/gammons/slk/releases/latest", "--jq", '.tag_name | ltrimstr("v")'], {
    stdin: "ignore",
    stdout: "pipe",
    stderr: "inherit",
  });
  // gh has already said what went wrong; exit with its code, like set -e did.
  if (gh.exitCode !== 0) process.exit(gh.exitCode ?? 1);
  const latestSlk = gh.stdout.toString().replace(/\n+$/, "");
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

// --- KernelSU modules (mobile/android/devices/*/root/sources.json) ---------------------------
// nix/mobile/android-root.nix reads url and hash; version is what this compares. Three kinds:
// a GitHub release asset matched by a regex, the head commit of a branch (a module repository
// that is itself the flashable tree), and a file listed on a plain HTML index page.
interface RootSource {
  type: "github-release" | "github-commit" | "html-index";
  repo?: string;
  branch?: string;
  index?: string;
  asset?: string;
  version: string;
  url: string;
  hash: string;
}

// The workflow's token lifts GitHub's 60 requests an hour for unauthenticated calls.
async function githubJson<T>(path: string): Promise<T> {
  const token = process.env.GH_TOKEN;
  const res = await fetch(`https://api.github.com/${path}`, {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
    signal: AbortSignal.timeout(30_000),
  });
  if (!res.ok) throw new Fatal(`github ${path}: HTTP ${res.status}`);
  return res.json() as T;
}

async function latestRootSource(src: RootSource): Promise<{ version: string; url: string }> {
  switch (src.type) {
    case "github-release": {
      const rel = await githubJson<{ tag_name: string; assets: { name: string; browser_download_url: string }[] }>(
        `repos/${src.repo}/releases/latest`,
      );
      const re = new RegExp(src.asset ?? "");
      const asset = rel.assets.find((a) => re.test(a.name));
      if (!asset) throw new Fatal(`${src.repo} ${rel.tag_name}: no asset matches ${src.asset}`);
      return { version: rel.tag_name, url: asset.browser_download_url };
    }
    case "github-commit": {
      const c = await githubJson<{ sha: string }>(`repos/${src.repo}/commits/${src.branch}`);
      return { version: c.sha, url: `https://github.com/${src.repo}/archive/${c.sha}.tar.gz` };
    }
    case "html-index": {
      // Pick the highest version-looking name among the matching links.
      const html = await (await get(src.index ?? "", 30_000)).text();
      const re = new RegExp(src.asset ?? "");
      const names = [...new Set([...html.matchAll(/href="([^"]+)"/g)].map((m) => m[1]))].filter((n) => re.test(n));
      const key = (n: string): number[] => (n.match(/\d+/g) ?? []).map(Number);
      names.sort((a, b) => {
        const [x, y] = [key(a), key(b)];
        for (let i = 0; i < Math.max(x.length, y.length); i++) if ((x[i] ?? 0) !== (y[i] ?? 0)) return (x[i] ?? 0) - (y[i] ?? 0);
        return 0;
      });
      const name = names.at(-1);
      if (!name) throw new Fatal(`${src.index}: no link matches ${src.asset}`);
      return { version: name, url: new URL(name, src.index).href };
    }
  }
}

async function updateAndroidRoot(): Promise<void> {
  const devices = `${repo}/mobile/android/devices`;
  for (const device of readdirSync(devices).sort()) {
    const file = `${devices}/${device}/root/sources.json`;
    if (!existsSync(file)) continue;
    const sources = JSON.parse(readFileSync(file, "utf8")) as Record<string, RootSource>;
    let changed = false;
    for (const [name, src] of Object.entries(sources)) {
      const latest = await latestRootSource(src);
      if (latest.version === src.version) continue;
      const hash = sriSha256(await getBytes(latest.url));
      out(`android-root ${device}/${name}: ${src.version} -> ${latest.version}`);
      Object.assign(src, latest, { hash });
      changed = true;
    }
    if (changed) writeFileSync(file, `${JSON.stringify(sources, null, 2)}\n`);
  }
}

try {
  await updateSlk();
  await updateUnity();
  await updateFabric();
  await updateGeyser();
  await updateAndroidRoot();
} catch (e) {
  err(`update-custom-packages: ${e instanceof Error ? e.message : String(e)}`);
  process.exit(1);
}
