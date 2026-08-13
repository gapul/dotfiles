#!/usr/bin/env python3
"""Kvaesitso (ランチャー) のテーマを configs/theme/palettes.json から生成する。

ランチャーのバックアップ全体はバージョン間で互換が無いバイナリなので repo に
置いても差分が見えない。一方テーマだけは独立した JSON (ThemeBundle v2) で
書き出せるので、母艦や tmux や Windows と同じ palettes.json を SSOT にできる。

    ./launcher-theme.py            # 標準出力に JSON
    ./launcher-theme.py --check    # 生成物が Kvaesitso の形式を満たすか検証

色は 2 通りの書き方があり (`#AARRGGBB` の直値と `$primary.40` のパレット参照)、
ここでは全ロールを直値で埋める。参照はコアパレットからトーンを機械生成する
仕組みで、rose-pine のように手で選んだ色を並べたパレットとは噛み合わない。
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
import uuid
from pathlib import Path

REPO_ROOT = Path(
    subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
)
PALETTES = REPO_ROOT / "configs/theme/palettes.json"

# Material 3 のロール名。Kvaesitso の ColorScheme がこの一式を期待する
# (data/themes/.../colors/Colors.kt)。欠けるとその色だけ既定値に落ちる。
ROLES = [
    "primary", "onPrimary", "primaryContainer", "onPrimaryContainer",
    "secondary", "onSecondary", "secondaryContainer", "onSecondaryContainer",
    "tertiary", "onTertiary", "tertiaryContainer", "onTertiaryContainer",
    "error", "onError", "errorContainer", "onErrorContainer",
    "surface", "onSurface", "onSurfaceVariant", "surfaceVariant",
    "surfaceDim", "surfaceBright",
    "surfaceContainerLowest", "surfaceContainerLow", "surfaceContainer",
    "surfaceContainerHigh", "surfaceContainerHighest",
    "outline", "outlineVariant",
    "inverseSurface", "inverseOnSurface", "inversePrimary",
    "background", "onBackground", "surfaceTint", "scrim",
]


def scheme(p: dict) -> dict:
    """rose-pine の色名を Material 3 のロールに割り当てる。

    アクセント 3 色は iris / foam / rose を当てる。rose-pine 自身が
    「背景 3 段 + 前景 3 段 + アクセント」の構成なので、M3 の surface 階層は
    base -> surface -> overlay -> hlMed の順に濃くしていけば素直に嵌まる。
    """
    c = lambda k: "#FF" + p[k].upper()  # noqa: E731 — 直値は #AARRGGBB
    return {
        "primary": c("iris"), "onPrimary": c("base"),
        "primaryContainer": c("overlay"), "onPrimaryContainer": c("text"),
        "secondary": c("foam"), "onSecondary": c("base"),
        "secondaryContainer": c("overlay"), "onSecondaryContainer": c("text"),
        "tertiary": c("rose"), "onTertiary": c("base"),
        "tertiaryContainer": c("overlay"), "onTertiaryContainer": c("text"),
        "error": c("love"), "onError": c("base"),
        "errorContainer": c("overlay"), "onErrorContainer": c("text"),
        "surface": c("base"), "onSurface": c("text"),
        "onSurfaceVariant": c("subtle"), "surfaceVariant": c("overlay"),
        "surfaceDim": c("base"), "surfaceBright": c("overlay"),
        "surfaceContainerLowest": c("base"), "surfaceContainerLow": c("surface"),
        "surfaceContainer": c("surface"), "surfaceContainerHigh": c("overlay"),
        "surfaceContainerHighest": c("hlMed"),
        "outline": c("muted"), "outlineVariant": c("hlMed"),
        "inverseSurface": c("text"), "inverseOnSurface": c("base"),
        "inversePrimary": c("iris"),
        "background": c("base"), "onBackground": c("text"),
        "surfaceTint": c("iris"), "scrim": c("base"),
    }


def build() -> dict:
    data = json.loads(PALETTES.read_text())
    palettes = data["palettes"]
    active = data["active"]

    # ライトはドーンで固定する。Kvaesitso は 1 つのテーマに light/dark を両方
    # 持たせて OS の外観に追従するので、active がどちらでも中身は同じになる。
    dark = next(p for p in palettes.values() if p["variant"] == "dark")
    light = next(p for p in palettes.values() if p["variant"] == "light")

    return {
        "name": active,
        "author": "gapul/dotfiles (configs/theme/palettes.json から生成)",
        "version": 2,
        "colors": {
            # 端末側はテーマを id で同定する。毎回変わると取り込むたびに
            # 別テーマとして増えるので、名前から決定的に導く。
            "id": str(uuid.uuid5(uuid.NAMESPACE_URL, f"net.gapul.kvaesitso.{active}")),
            "name": active,
            "lightColorScheme": scheme(light),
            "darkColorScheme": scheme(dark),
        },
    }


def check(bundle: dict) -> int:
    problems = []
    if bundle.get("version") != 2:
        problems.append("version が 2 でない (旧形式として読まれる)")
    for kind in ("lightColorScheme", "darkColorScheme"):
        s = bundle["colors"][kind]
        for missing in sorted(set(ROLES) - set(s)):
            problems.append(f"{kind}: ロール {missing} が無い")
        for role, value in sorted(s.items()):
            if not re.fullmatch(r"#[0-9A-F]{8}", value):
                problems.append(f"{kind}.{role}: {value} は #AARRGGBB でない")
    for p in problems:
        print(f"  {p}", file=sys.stderr)
    if problems:
        print(f"{len(problems)} 件の問題", file=sys.stderr)
        return 1
    print(f"ok: {len(ROLES)} ロール x light/dark")
    return 0


if __name__ == "__main__":
    theme = build()
    if "--check" in sys.argv[1:]:
        raise SystemExit(check(theme))
    print(json.dumps(theme, indent=2, ensure_ascii=False))
