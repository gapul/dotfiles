#!/usr/bin/env bun
// Kvaesitso (ランチャー) のテーマを configs/theme/palettes.json から生成する。
//
// ランチャーのバックアップ全体はバージョン間で互換が無いバイナリなので repo に
// 置いても差分が見えない。一方テーマだけは独立した JSON (ThemeBundle v2) で
// 書き出せるので、母艦や tmux や Windows と同じ palettes.json を SSOT にできる。
//
//     ./launcher-theme.ts            # 標準出力に JSON
//     ./launcher-theme.ts --check    # 生成物が Kvaesitso の形式を満たすか検証
//
// 色は 2 通りの書き方があり (`#AARRGGBB` の直値と `$primary.40` のパレット参照)、
// ここでは全ロールを直値で埋める。参照はコアパレットからトーンを機械生成する
// 仕組みで、rose-pine のように手で選んだ色を並べたパレットとは噛み合わない。
//
// Ported from mobile/android/launcher-theme.py; the JSON output is byte-identical.
import { createHash } from "node:crypto";
import { readFileSync, writeSync } from "node:fs";
import { join } from "node:path";

const out = (line: string): void => void writeSync(1, `${line}\n`);
const err = (line: string): void => void writeSync(2, `${line}\n`);

const gitTop = Bun.spawnSync(["git", "rev-parse", "--show-toplevel"], {
  stdin: "ignore",
  stdout: "pipe",
  stderr: "inherit",
});
if (gitTop.exitCode !== 0) process.exit(gitTop.exitCode ?? 1);
const REPO_ROOT = gitTop.stdout.toString().trim();
const PALETTES = join(REPO_ROOT, "configs/theme/palettes.json");

// Material 3 のロール名。Kvaesitso の ColorScheme がこの一式を期待する
// (data/themes/.../colors/Colors.kt)。欠けるとその色だけ既定値に落ちる。
const ROLES = [
  "primary",
  "onPrimary",
  "primaryContainer",
  "onPrimaryContainer",
  "secondary",
  "onSecondary",
  "secondaryContainer",
  "onSecondaryContainer",
  "tertiary",
  "onTertiary",
  "tertiaryContainer",
  "onTertiaryContainer",
  "error",
  "onError",
  "errorContainer",
  "onErrorContainer",
  "surface",
  "onSurface",
  "onSurfaceVariant",
  "surfaceVariant",
  "surfaceDim",
  "surfaceBright",
  "surfaceContainerLowest",
  "surfaceContainerLow",
  "surfaceContainer",
  "surfaceContainerHigh",
  "surfaceContainerHighest",
  "outline",
  "outlineVariant",
  "inverseSurface",
  "inverseOnSurface",
  "inversePrimary",
  "background",
  "onBackground",
  "surfaceTint",
  "scrim",
];

type Palette = Record<string, string>;
type Scheme = Record<string, string>;

interface Bundle {
  name: string;
  author: string;
  version: number;
  colors: {
    id: string;
    name: string;
    lightColorScheme: Scheme;
    darkColorScheme: Scheme;
  };
}

// rose-pine の色名を Material 3 のロールに割り当てる。
//
// アクセント 3 色は iris / foam / rose を当てる。rose-pine 自身が
// 「背景 3 段 + 前景 3 段 + アクセント」の構成なので、M3 の surface 階層は
// base -> surface -> overlay -> hlMed の順に濃くしていけば素直に嵌まる。
function scheme(p: Palette): Scheme {
  const c = (k: string): string => {
    // 直値は #AARRGGBB
    if (!Object.hasOwn(p, k)) throw new Error(`palette has no color ${k}`);
    return "#FF" + p[k].toUpperCase();
  };
  return {
    primary: c("iris"),
    onPrimary: c("base"),
    primaryContainer: c("overlay"),
    onPrimaryContainer: c("text"),
    secondary: c("foam"),
    onSecondary: c("base"),
    secondaryContainer: c("overlay"),
    onSecondaryContainer: c("text"),
    tertiary: c("rose"),
    onTertiary: c("base"),
    tertiaryContainer: c("overlay"),
    onTertiaryContainer: c("text"),
    error: c("love"),
    onError: c("base"),
    errorContainer: c("overlay"),
    onErrorContainer: c("text"),
    surface: c("base"),
    onSurface: c("text"),
    onSurfaceVariant: c("subtle"),
    surfaceVariant: c("overlay"),
    surfaceDim: c("base"),
    surfaceBright: c("overlay"),
    surfaceContainerLowest: c("base"),
    surfaceContainerLow: c("surface"),
    surfaceContainer: c("surface"),
    surfaceContainerHigh: c("overlay"),
    surfaceContainerHighest: c("hlMed"),
    outline: c("muted"),
    outlineVariant: c("hlMed"),
    inverseSurface: c("text"),
    inverseOnSurface: c("base"),
    inversePrimary: c("iris"),
    background: c("base"),
    onBackground: c("text"),
    surfaceTint: c("iris"),
    scrim: c("base"),
  };
}

// RFC 4122 name-based UUID (SHA-1), the same value as Python's uuid.uuid5.
const NAMESPACE_URL = "6ba7b811-9dad-11d1-80b4-00c04fd430c8";
function uuid5(namespace: string, name: string): string {
  const ns = Buffer.from(namespace.replaceAll("-", ""), "hex");
  const hash = createHash("sha1").update(ns).update(name, "utf8").digest().subarray(0, 16);
  hash[6] = (hash[6] & 0x0f) | 0x50;
  hash[8] = (hash[8] & 0x3f) | 0x80;
  const hex = hash.toString("hex");
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20, 32),
  ].join("-");
}

function build(): Bundle {
  const data = JSON.parse(readFileSync(PALETTES, "utf8")) as {
    palettes: Record<string, Palette>;
    active: string;
  };
  const palettes = Object.values(data.palettes);
  const active = data.active;

  // ライトはドーンで固定する。Kvaesitso は 1 つのテーマに light/dark を両方
  // 持たせて OS の外観に追従するので、active がどちらでも中身は同じになる。
  const dark = palettes.find((p) => p.variant === "dark");
  const light = palettes.find((p) => p.variant === "light");
  if (!dark || !light) throw new Error(`${PALETTES}: needs one dark and one light palette`);

  return {
    name: active,
    author: "gapul/dotfiles (configs/theme/palettes.json から生成)",
    version: 2,
    colors: {
      // 端末側はテーマを id で同定する。毎回変わると取り込むたびに
      // 別テーマとして増えるので、名前から決定的に導く。
      id: uuid5(NAMESPACE_URL, `net.gapul.kvaesitso.${active}`),
      name: active,
      lightColorScheme: scheme(light),
      darkColorScheme: scheme(dark),
    },
  };
}

const byteSort = (xs: string[]): string[] => [...xs].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));

function check(bundle: Bundle): number {
  const problems: string[] = [];
  if (bundle.version !== 2) problems.push("version が 2 でない (旧形式として読まれる)");
  for (const kind of ["lightColorScheme", "darkColorScheme"] as const) {
    const s = bundle.colors[kind];
    for (const missing of byteSort(ROLES.filter((r) => !Object.hasOwn(s, r)))) {
      problems.push(`${kind}: ロール ${missing} が無い`);
    }
    for (const role of byteSort(Object.keys(s))) {
      const value = s[role];
      if (!/^#[0-9A-F]{8}$/.test(value)) problems.push(`${kind}.${role}: ${value} は #AARRGGBB でない`);
    }
  }
  for (const p of problems) err(`  ${p}`);
  if (problems.length > 0) {
    err(`${problems.length} 件の問題`);
    return 1;
  }
  out(`ok: ${ROLES.length} ロール x light/dark`);
  return 0;
}

const theme = build();
if (Bun.argv.slice(2).includes("--check")) process.exit(check(theme));
out(JSON.stringify(theme, null, 2));
