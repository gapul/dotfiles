#!/usr/bin/env bun
// ドキュメント内の生成ブロックを設定 (SSOT) から再生成する。
//
// 各ブロックは Markdown コメントのマーカー
//     <!-- BEGIN <name> --> ... <!-- END <name> -->
// で囲まれ、中身は下の BLOCKS で定義した生成関数の出力に差し替えられる。
//
// 使い方:
//     gen-docs.ts            # ファイルを書き換える (just docs から呼ぶ)
//     gen-docs.ts --check    # 書き換えず、ドリフトがあれば diff を出して exit 1 (CI 用)
//
// 生成対象は「設定から機械的に導ける事実」だけに限定する。設計判断や
// トラブルシューティングなど "なぜ" の散文はマーカー外の手書きのまま残す。
//
// Ported from scripts/gen-docs.py. The generated blocks are byte-identical; the --check diff
// now comes from `diff -u` instead of Python's difflib (same unified format and labels).
import { mkdtempSync, readFileSync, rmSync, writeFileSync, writeSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const out = (line: string): void => void writeSync(1, `${line}\n`);
const err = (line: string): void => void writeSync(2, `${line}\n`);

// Captures stdout and stderr like subprocess.run(capture_output=True, check=True); stderr is
// shown only when the command fails.
function run(cmd: string[], cwd?: string): string {
  const p = Bun.spawnSync(cmd, { cwd, stdin: "ignore", stdout: "pipe", stderr: "pipe" });
  if (p.exitCode !== 0) {
    writeSync(2, p.stderr.toString());
    throw new Error(`command failed (exit ${p.exitCode}): ${cmd.join(" ")}`);
  }
  return p.stdout.toString();
}

const REPO_ROOT = run(["git", "rev-parse", "--show-toplevel"]).trim();
const FLAKE = "./nix";

const repoRun = (cmd: string[]): string => run(cmd, REPO_ROOT);

function nixEvalJson(attr: string, apply?: string): unknown {
  const cmd = ["nix", "eval", "--json", `${FLAKE}#${attr}`];
  if (apply !== undefined) cmd.push("--apply", apply);
  return JSON.parse(repoRun(cmd));
}

// fork 先でも動くよう user.nix から username を引く。
const username = (): string =>
  repoRun(["nix", "eval", "--raw", "-f", "./nix/user.nix", "username"]).trim();

// Python's sorted() on str: code point order, not localeCompare.
const byteSort = (xs: string[]): string[] => [...xs].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));

// --- 各ブロックの生成関数 --------------------------------------------------

// Justfile のレシピ一覧 (`just --list` そのまま)。
function genJustList(): string {
  const body = repoRun(["just", "--list", "--list-heading", ""]).replace(/^\n+|\n+$/g, "");
  return "```text\n" + body + "\n```";
}

// pre-commit フックの人間向け説明。フックの enable/対象/除外は nix eval が
// 唯一の真実。説明だけはここで一元管理し、新フック追加時は `just docs` が
// "—" を出すので追記に気付ける。
const HOOK_DESCRIPTIONS: Record<string, string> = {
  nixfmt: "Formatting check. Fails on anything unformatted.",
  deadnix: "Finds unused code. Module arguments like `{ lib, ... }` are allowed.",
  shellcheck: "Shell lint, following .shellcheckrc",
  gitleaks: "Secret detection",
  ruff: "Python lint (pyproject.toml), applying safe autofixes",
  "ruff-format": "Python formatting",
  pyright: "Python type check, basic mode (pyproject.toml)",
};

function filesToTarget(files: string): string {
  const mapping: Record<string, string> = {
    "": "all staged",
    "\\.nix$": "`*.nix`",
    "\\.py$": "`*.py`",
  };
  return Object.hasOwn(mapping, files) ? mapping[files] : `\`${files}\``;
}

interface Hook {
  enable: boolean;
  files?: string;
  excludes?: string[];
}

// 有効な pre-commit フック一覧 (git-hooks.nix の宣言から)。
function genHooks(): string {
  const hooks = nixEvalJson(
    "checks.aarch64-darwin.pre-commit.config.hooks",
    "hs: builtins.listToAttrs (builtins.filter (x: x.value.enable) " +
      "(map (n: { name = n; value = { " +
      "enable = hs.${n}.enable; " +
      'files = hs.${n}.files or ""; ' +
      "excludes = hs.${n}.excludes or []; " +
      "}; }) (builtins.attrNames hs)))",
  ) as Record<string, Hook>;
  const lines = ["| Hook | Target | Excluded | What it does |", "|---|---|---|---|"];
  for (const name of byteSort(Object.keys(hooks))) {
    const h = hooks[name];
    const target = filesToTarget(h.files ?? "");
    const excludes = h.excludes ?? [];
    const excl = excludes.length > 0 ? excludes.map((e) => `\`${e}\``).join(", ") : "—";
    const desc = Object.hasOwn(HOOK_DESCRIPTIONS, name) ? HOOK_DESCRIPTIONS[name] : "—";
    lines.push(`| \`${name}\` | ${target} | ${excl} | ${desc} |`);
  }
  return lines.join("\n");
}

// 全 shell alias 一覧。
//
// 出どころが 2 つあるので両方を混ぜる:
//   - home-manager の shellAliases (母艦固有 + programs.eza 等が足すもの)
//   - configs/shell/zshrc.common (母艦と nssh 先が共有する可搬な alias)
// 後者は shell.nix から抜き出したもので、拾わないと一覧から消えてしまう。
function genAliases(): string {
  const user = username();
  const aliases = new Map(
    Object.entries(
      nixEvalJson(`homeConfigurations.${user}.config.programs.zsh.shellAliases`) as Record<
        string,
        string
      >,
    ),
  );
  // 共有ファイル側。条件付き (if の中) の alias は字下げしてあるので、
  // 行頭の alias だけを拾えば「常に効くもの」だけが集まる。
  let shared: string | undefined;
  try {
    shared = readFileSync(join(REPO_ROOT, "configs/shell/zshrc.common"), "utf8");
  } catch {
    shared = undefined;
  }
  if (shared !== undefined) {
    for (const line of splitLines(shared)) {
      const m = /^alias\s+([^=\s]+)='(.*)'\s*$/.exec(line);
      if (m && !aliases.has(m[1])) aliases.set(m[1], m[2]);
    }
  }
  // ホームディレクトリの絶対パスは fork 先で変わるので伏せる。
  const home = `/Users/${user}`;
  const lines = ["| alias | Expands to |", "|---|---|"];
  for (const name of byteSort([...aliases.keys()])) {
    const expansion = (aliases.get(name) ?? "").replaceAll(home, "~");
    lines.push(`| \`${name}\` | \`${expansion}\` |`);
  }
  return lines.join("\n");
}

// str.splitlines() for the line endings a shell rc can contain.
const splitLines = (text: string): string[] => {
  const lines = text.split(/\r\n|\r|\n/);
  if (lines.length > 0 && lines[lines.length - 1] === "") lines.pop();
  return lines;
};

// --- ブロック定義 ----------------------------------------------------------

const BLOCKS: [string, string, () => string][] = [
  ["README.md", "just-list", genJustList],
  ["README.md", "hooks", genHooks],
  ["docs/CHEATSHEET.md", "aliases", genAliases],
];

function inject(text: string, name: string, body: string): string {
  const begin = `<!-- BEGIN ${name} -->`;
  const end = `<!-- END ${name} -->`;
  if (!text.includes(begin) || !text.includes(end)) {
    err(`marker ${begin} / ${end} not found`);
    process.exit(1);
  }
  const b = text.indexOf(begin);
  const pre = text.slice(0, b);
  const rest = text.slice(b + begin.length);
  const post = rest.slice(rest.indexOf(end) + end.length);
  return `${pre}${begin}\n${body}\n${end}${post}`;
}

// Unified diff of the would-be rewrite, labelled like the git-style a/ b/ paths.
function showDiff(rel: string, original: string, updated: string): void {
  const dir = mkdtempSync(join(tmpdir(), "gen-docs-"));
  try {
    const a = join(dir, "a");
    const b = join(dir, "b");
    writeFileSync(a, original);
    writeFileSync(b, updated);
    const p = Bun.spawnSync(["diff", "-u", "--label", `a/${rel}`, "--label", `b/${rel}`, a, b], {
      stdin: "ignore",
      stdout: "pipe",
      stderr: "inherit",
    });
    writeSync(1, p.stdout.toString());
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

function main(): number {
  const check = Bun.argv.slice(2).includes("--check");
  const drifted: string[] = [];
  // ファイル単位でまとめて処理 (同一ファイルに複数ブロックがあるため)。
  const byFile = new Map<string, [string, () => string][]>();
  for (const [rel, name, fn] of BLOCKS) {
    const entries = byFile.get(rel) ?? [];
    entries.push([name, fn]);
    byFile.set(rel, entries);
  }

  for (const [rel, entries] of byFile) {
    const path = join(REPO_ROOT, rel);
    const original = readFileSync(path, "utf8");
    let updated = original;
    for (const [name, fn] of entries) updated = inject(updated, name, fn());
    if (updated === original) continue;
    if (check) {
      showDiff(rel, original, updated);
      drifted.push(rel);
    } else {
      writeFileSync(path, updated);
      out(`regenerated: ${rel}`);
    }
  }

  if (check && drifted.length > 0) {
    err(
      `\ndocs have drifted from the configuration: ${drifted.join(", ")}\n` +
        "Run `just docs` and commit the result.",
    );
    return 1;
  }
  if (!check) out("regenerated the generated doc blocks; check with git diff");
  return 0;
}

process.exit(main());
