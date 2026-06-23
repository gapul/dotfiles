#!/usr/bin/env python3
"""
GUI アプリの plist を filter + XML 化して dotfiles に capture する汎用ツール。

使い方:
    capture-app-plist.py <src> <dst> [<exclude_pattern>...]

- src: 元 plist (絶対 path)
- dst: 出力先 (絶対 path、binary 形式で書いてから plutil で XML 化される)
- exclude_pattern: glob 風パターン (例: "MS*", "NSWindow Frame*", "SU*")
  マッチした key を root から除外して保存する。
"""
import fnmatch
import plistlib
import subprocess
import sys
from pathlib import Path


def main():
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    src = Path(sys.argv[1]).expanduser()
    dst = Path(sys.argv[2]).expanduser()
    patterns = sys.argv[3:]

    if not src.exists():
        print(f"ERROR: source not found: {src}", file=sys.stderr)
        sys.exit(1)

    with open(src, "rb") as f:
        pl = plistlib.load(f)

    if patterns:
        before = len(pl)
        for k in list(pl):
            if any(fnmatch.fnmatchcase(k, p) for p in patterns):
                del pl[k]
        print(f"  filtered {before - len(pl)} key(s) matching {patterns}")

    dst.parent.mkdir(parents=True, exist_ok=True)
    with open(dst, "wb") as f:
        plistlib.dump(pl, f)
    subprocess.run(["plutil", "-convert", "xml1", str(dst)], check=True)
    print(f"  → {dst} ({len(pl)} key(s))")


if __name__ == "__main__":
    main()
