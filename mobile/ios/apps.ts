#!/usr/bin/env bun
// apps.tsv に宣言したアプリと実機を突き合わせる。Android 側の apps.ts と同じ役割だが、
// iOS には入れる手段が無いので status と verify だけ。
//
//   ./apps.ts status   # USB 接続した iPhone と宣言の差分。MISSING があれば exit 1 (既定)
//   ./apps.ts verify   # appstore 行の bundleId が実在するか (iTunes Search API)
//
// AltStore は再署名のときに bundleId へ team id を足す (`net.gapul.blink` が
// 実機では `net.gapul.blink.S3H296G6Q5`、AltStore 自体は `com.S3H296G6Q5.` 接頭辞)。
// 宣言には配布元の id を書き、実機側を正規化して突き合わせる。
//
// status には USB 接続と、端末側で「このコンピュータを信頼」済みであることが要る。
// ネットワーク越しには照会できない。
//
// Ported from apps.sh. ideviceinstaller stays an external command so test.sh can put a fake
// one on PATH; the HTTP lookups in verify use fetch.
import { readFileSync, writeSync } from "node:fs";

process.chdir(import.meta.dir);

const out = (line: string): void => void writeSync(1, `${line}\n`);
const err = (line: string): void => void writeSync(2, `${line}\n`);

// 再署名で bundleId に差し込まれる team id。configs/bin/ios と同じ値。
const TEAM_ID = "S3H296G6Q5";

const byteSort = (xs: string[]): string[] => [...xs].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));

// Same split as `IFS=$'\t' read -r a b c`: tabs are IFS whitespace, so runs collapse into one
// separator, and the last variable takes the rest of the line.
function readFields(line: string, n: number): string[] {
  let rest = line.replace(/^\t+/, "").replace(/\t+$/, "");
  const fields: string[] = [];
  for (let i = 0; i < n - 1; i++) {
    const m = /^([^\t]*)\t+/.exec(rest);
    if (!m) {
      fields.push(rest);
      rest = "";
      continue;
    }
    fields.push(m[1]);
    rest = rest.slice(m[0].length);
  }
  fields.push(rest);
  return fields;
}

// Lines that are neither blank nor comments (grep -vE '^[[:space:]]*(#|$)').
const dataLines = (file: string): string[] =>
  readFileSync(file, "utf8")
    .replace(/\n$/, "")
    .split("\n")
    .filter((l) => !/^\s*(#|$)/.test(l));

interface Declared {
  line: string;
  bundle: string;
  source: string;
  name: string;
}

function declared(): Declared[] {
  return dataLines("apps.tsv").map((line) => {
    const [bundle, source, name] = readFields(line, 4);
    return { line, bundle, source, name };
  });
}

// 実機の id を配布元の id に戻す。接尾辞と接頭辞の 2 パターンがある。
const denormalize = (id: string): string =>
  id.replace(new RegExp(`\\.${TEAM_ID}$`), "").replace(new RegExp(`^com\\.${TEAM_ID}\\.`), "");

function cmdStatus(): number {
  if (!Bun.which("ideviceinstaller")) {
    err("ideviceinstaller が無い: nix shell nixpkgs#ideviceinstaller (just ios-apps なら自動)");
    return 1;
  }

  // 出力は "bundleId, \"version\", \"name\"" の CSV で 1 行目がヘッダ。
  // bundleId だけ抜き、ヘッダ (CFBundleIdentifier) は落とす。
  const p = Bun.spawnSync(["ideviceinstaller", "list"], { stdin: "inherit", stdout: "pipe", stderr: "inherit" });
  if (p.exitCode !== 0) return p.exitCode ?? 1;
  const body = p.stdout.toString().replace(/\n$/, "");
  const installed = byteSort(
    (body === "" ? [] : body.split("\n"))
      .map((l) => l.split(",")[0])
      .filter((id) => id !== "CFBundleIdentifier")
      .map((id) => denormalize(id.replace(/\s+$/, ""))),
  );
  const installedSet = new Set(installed);
  let missing = 0;
  let extra = 0;

  out("━━━ 宣言したが端末に無い ━━━");
  for (const { bundle, source, name } of declared()) {
    if (!installedSet.has(bundle)) {
      out(`  MISSING  ${name} (${source}) — ${bundle}`);
      missing++;
    }
  }
  if (missing === 0) out("  なし");

  out("━━━ 端末に在るが宣言に無い ━━━");
  const declaredIds = new Set(declared().map((d) => d.line.split("\t")[0]));
  for (const raw of installed) {
    const bundle = raw.trim();
    if (bundle === "") continue;
    if (!declaredIds.has(bundle)) {
      out(`  EXTRA    ${bundle}`);
      extra++;
    }
  }
  if (extra === 0) out("  なし");

  // Android 側と同じ判断: 宣言を満たしていないことだけを失敗にする。
  if (missing > 0) {
    err(`宣言 ${missing} 件が未インストール。App Store / AltStore から手で入れる`);
    return 1;
  }
  return 0;
}

async function getJson(url: string): Promise<unknown> {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${url}: HTTP ${res.status}`);
  return res.json();
}

// sources.tsv の該当 kind の source を全部引いて、bundleIdentifier を一覧にする。
// source は AltStore の JSON 形式なので、ここを見れば「宣言した bundleId が
// 本当にその経路から入るものか」を機械で確かめられる。
async function sourceBundles(kind: string): Promise<Set<string>> {
  const ids = new Set<string>();
  for (const line of dataLines("sources.tsv")) {
    const [, srcKind, url] = readFields(line, 3);
    if (!srcKind || srcKind !== kind) continue;
    const doc = (await getJson(url)) as { apps?: { bundleIdentifier?: string }[] };
    for (const app of doc.apps ?? []) ids.add(app.bundleIdentifier ?? "");
  }
  return ids;
}

async function inAppStore(bundle: string): Promise<boolean> {
  try {
    const doc = (await getJson(`https://itunes.apple.com/lookup?bundleId=${bundle}&country=jp`)) as {
      resultCount: number;
    };
    return doc.resultCount > 0;
  } catch (e) {
    err(String(e));
    return false;
  }
}

async function cmdVerify(): Promise<number> {
  let unknown = 0;
  // source は行ごとに引かず 1 回だけ引く。宣言の数だけ HTTP を叩かない。
  let classic: Set<string>;
  let pal: Set<string>;
  try {
    classic = await sourceBundles("classic");
    pal = await sourceBundles("pal");
  } catch (e) {
    err(String(e));
    return 1;
  }

  for (const { bundle, source, name } of declared()) {
    let ok = true;
    switch (source) {
      case "appstore":
        ok = await inAppStore(bundle);
        break;
      case "altstore-classic":
        ok = classic.has(bundle);
        break;
      case "altstore-pal":
        ok = pal.has(bundle);
        break;
      // 配布元が AltStore 形式の JSON を出していないもの (PAL のマーケットプレイス
      // アプリ本体、Epic Games、まだ source に載せていない自ビルドなど)。
      // 経路は把握しているが機械では確かめられないので素通しする。
      case "manual":
        break;
      default:
        out(`  BAD      ${name} — source 列が不正: ${source}`);
        unknown++;
        continue;
    }
    if (!ok) {
      out(`  UNKNOWN  ${name} — ${source} に ${bundle} が無い`);
      unknown++;
    }
  }

  if (unknown > 0) {
    err(`${unknown} 件の bundleId が解決できない`);
    return 1;
  }
  out("宣言したアプリはすべて経路上に実在する");
  return 0;
}

const commands: Record<string, () => number | Promise<number>> = {
  status: cmdStatus,
  verify: cmdVerify,
};

const cmd = Bun.argv[2] || "status";
const handler = Object.hasOwn(commands, cmd) ? commands[cmd] : undefined;
if (!handler) {
  err("usage: ./apps.ts [status|verify]");
  process.exit(2);
}
process.exit(await handler());
