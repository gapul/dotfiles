#!/usr/bin/env python3
"""ドキュメント内の生成ブロックを設定 (SSOT) から再生成する。

各ブロックは Markdown コメントのマーカー
    <!-- BEGIN <name> --> ... <!-- END <name> -->
で囲まれ、中身は下の BLOCKS で定義した生成関数の出力に差し替えられる。

使い方:
    gen-docs.py            # ファイルを書き換える (just docs から呼ぶ)
    gen-docs.py --check    # 書き換えず、ドリフトがあれば diff を出して exit 1 (CI 用)

生成対象は「設定から機械的に導ける事実」だけに限定する。設計判断や
トラブルシューティングなど "なぜ" の散文はマーカー外の手書きのまま残す。
"""

from __future__ import annotations

import difflib
import json
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(
    subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
)
FLAKE = "./nix"


def _run(cmd: list[str]) -> str:
    return subprocess.run(
        cmd, cwd=REPO_ROOT, check=True, capture_output=True, text=True
    ).stdout


def _nix_eval_json(attr: str, apply: str | None = None) -> object:
    cmd = ["nix", "eval", "--json", f"{FLAKE}#{attr}"]
    if apply is not None:
        cmd += ["--apply", apply]
    return json.loads(_run(cmd))


def _username() -> str:
    """fork 先でも動くよう user.nix から username を引く。"""
    return _run(["nix", "eval", "--raw", "-f", "./nix/user.nix", "username"]).strip()


# --- 各ブロックの生成関数 --------------------------------------------------


def gen_just_list() -> str:
    """Justfile のレシピ一覧 (`just --list` そのまま)。"""
    body = _run(["just", "--list", "--list-heading", ""]).strip("\n")
    return "```text\n" + body + "\n```"


# pre-commit フックの人間向け説明。フックの enable/対象/除外は nix eval が
# 唯一の真実。説明だけはここで一元管理し、新フック追加時は `just docs` が
# "—" を出すので追記に気付ける。
HOOK_DESCRIPTIONS = {
    "nixfmt": "Formatting check. Fails on anything unformatted.",
    "deadnix": "Finds unused code. Module arguments like `{ lib, ... }` are allowed.",
    "shellcheck": "Shell lint, following .shellcheckrc",
    "gitleaks": "Secret detection",
}


def _files_to_target(files: str) -> str:
    mapping = {
        "": "all staged",
        r"\.nix$": "`*.nix`",
    }
    if files in mapping:
        return mapping[files]
    return f"`{files}`"


def gen_hooks() -> str:
    """有効な pre-commit フック一覧 (git-hooks.nix の宣言から)。"""
    hooks = _nix_eval_json(
        "checks.aarch64-darwin.pre-commit.config.hooks",
        apply=(
            "hs: builtins.listToAttrs (builtins.filter (x: x.value.enable) "
            "(map (n: { name = n; value = { "
            "enable = hs.${n}.enable; "
            'files = hs.${n}.files or ""; '
            "excludes = hs.${n}.excludes or []; "
            "}; }) (builtins.attrNames hs)))"
        ),
    )
    lines = ["| Hook | Target | Excluded | What it does |", "|---|---|---|---|"]
    for name in sorted(hooks):
        h = hooks[name]
        target = _files_to_target(h.get("files", ""))
        excludes = h.get("excludes", [])
        excl = ", ".join(f"`{e}`" for e in excludes) if excludes else "—"
        desc = HOOK_DESCRIPTIONS.get(name, "—")
        lines.append(f"| `{name}` | {target} | {excl} | {desc} |")
    return "\n".join(lines)


def gen_aliases() -> str:
    """全 shell alias 一覧。

    出どころが 2 つあるので両方を混ぜる:
      - home-manager の shellAliases (母艦固有 + programs.eza 等が足すもの)
      - configs/shell/zshrc.common (母艦と nssh 先が共有する可搬な alias)
    後者は shell.nix から抜き出したもので、拾わないと一覧から消えてしまう。
    """
    user = _username()
    aliases = _nix_eval_json(
        f"homeConfigurations.{user}.config.programs.zsh.shellAliases"
    )
    # 共有ファイル側。条件付き (if の中) の alias は字下げしてあるので、
    # 行頭の alias だけを拾えば「常に効くもの」だけが集まる。
    shared = REPO_ROOT / "configs/shell/zshrc.common"
    if shared.is_file():
        for line in shared.read_text().splitlines():
            m = re.match(r"^alias\s+([^=\s]+)='(.*)'\s*$", line)
            if m:
                aliases.setdefault(m.group(1), m.group(2))
    # ホームディレクトリの絶対パスは fork 先で変わるので伏せる。
    home = f"/Users/{user}"
    lines = ["| alias | 展開先 |", "|---|---|"]
    for name in sorted(aliases):
        expansion = aliases[name].replace(home, "~")
        lines.append(f"| `{name}` | `{expansion}` |")
    return "\n".join(lines)


# --- ブロック定義 ----------------------------------------------------------

BLOCKS = [
    ("README.md", "just-list", gen_just_list),
    ("README.md", "hooks", gen_hooks),
    ("docs/CHEATSHEET.md", "aliases", gen_aliases),
]


def _inject(text: str, name: str, body: str) -> str:
    begin, end = f"<!-- BEGIN {name} -->", f"<!-- END {name} -->"
    if begin not in text or end not in text:
        sys.exit(f"マーカー {begin} / {end} が見つからない")
    pre, rest = text.split(begin, 1)
    _, post = rest.split(end, 1)
    return f"{pre}{begin}\n{body}\n{end}{post}"


def main() -> int:
    check = "--check" in sys.argv[1:]
    drifted = []
    # ファイル単位でまとめて処理 (同一ファイルに複数ブロックがあるため)。
    by_file: dict[str, list[tuple[str, object]]] = {}
    for rel, name, fn in BLOCKS:
        by_file.setdefault(rel, []).append((name, fn))

    for rel, entries in by_file.items():
        path = REPO_ROOT / rel
        original = path.read_text()
        updated = original
        for name, fn in entries:
            updated = _inject(updated, name, fn())
        if updated == original:
            continue
        if check:
            diff = difflib.unified_diff(
                original.splitlines(keepends=True),
                updated.splitlines(keepends=True),
                fromfile=f"a/{rel}",
                tofile=f"b/{rel}",
            )
            sys.stdout.writelines(diff)
            drifted.append(rel)
        else:
            path.write_text(updated)
            print(f"regenerated: {rel}")

    if check and drifted:
        print(
            f"\nドキュメントが設定と乖離している: {', '.join(drifted)}\n"
            "`just docs` を実行して commit してください。",
            file=sys.stderr,
        )
        return 1
    if not check:
        print("ドキュメント生成ブロックを再生成した (git diff で確認)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
