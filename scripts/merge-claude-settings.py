#!/usr/bin/env python3
"""Merge the dotfiles-managed Claude Code settings into a host's settings.json.

nssh 先の ~/.claude/settings.json は permissions が承認のたびに育つホスト所有のファイル。
gh / codex のように symlink で丸ごと差し替えると、nssh の `reset --hard` で承認済みの
許可が毎回消える。そこでリポジトリが持つ管理キーだけを既存の JSON へ上書き merge する。
~/.bashrc に bashrc.remote を読む行だけ足すのと同じ考え方で、管理外のキー
(permissions / enabledPlugins / skipDangerousModePermissionPrompt) はホスト側に残す。

母艦は事情が違う。bypassPermissions なので permissions が育たず、settings.json をまるごと
nix の out-of-store symlink で持てる (nix/home/workstation.nix)。このスクリプトを母艦の
settings.json へ向けてはいけない。write_atomic が tmp+rename なので、symlink を実ファイルで
置き換えて追跡を切る。母艦は --adopt (読むだけ) の向きでだけ使う。

不正な JSON を掴んだときは何も書かずに失敗する。壊れた設定を上書きで
「直して」しまうと、ホスト側にしか無い permissions を巻き添えで捨てるため。

  適用: python3 scripts/merge-claude-settings.py ~/.claude/settings.json
  検査: python3 scripts/merge-claude-settings.py ~/.claude/settings.json --check
  吸上: python3 scripts/merge-claude-settings.py ~/.config/claude/settings.json --adopt
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import sys
import tempfile

SCRIPTS = pathlib.Path(__file__).resolve().parent
DEFAULT_MANAGED = SCRIPTS.parent / "configs/cli/claude/settings.remote.json"


def load_json(path: pathlib.Path) -> dict:
    """Read a JSON object. A missing or empty file is an empty object."""
    try:
        raw = path.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return {}
    if not raw:
        return {}
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise ValueError(f"{path}: JSON object ではない ({type(data).__name__})")
    return data


def merged(target: dict, managed: dict) -> dict:
    """Overlay the managed keys onto the target, keeping the target's key order.

    $schema は Claude Code が読む値ではなくエディタ補完用なので、既存ファイルが
    持っていなければ先頭に置く (手で開いたときに素性が分かるように)。
    """
    out = dict(target)
    for key, value in managed.items():
        out[key] = value
    if "$schema" in out:
        out = {"$schema": out.pop("$schema"), **out}
    return out


def write_atomic(path: pathlib.Path, data: dict) -> None:
    """Replace the file in one rename so a crash never leaves a half-written config."""
    path.parent.mkdir(parents=True, exist_ok=True)
    body = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=path.name + ".", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(body)
        os.replace(tmp, path)
    except BaseException:
        pathlib.Path(tmp).unlink(missing_ok=True)
        raise


def adopt(source: pathlib.Path, managed_path: pathlib.Path) -> int:
    """Pull the managed keys' current values out of a host's settings into the repo.

    「Claude の設定はクライアント端末を正とする」ための逆向きの経路。母艦で設定を
    いじったあとにこれを走らせると、その値がリポジトリに入り、次の nssh でリモートへ
    降りていく。管理キーの集合そのものは増やさない (permissions を吸い上げないため)。
    """
    try:
        managed = load_json(managed_path)
        current = load_json(source)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"[claude-settings] 読めません: {exc}", file=sys.stderr)
        return 1

    updated = dict(managed)
    changed = []
    missing = []
    for key in managed:
        if key == "$schema":
            continue
        if key not in current:
            missing.append(key)
            continue
        if current[key] != managed[key]:
            updated[key] = current[key]
            changed.append(f"{key}: {managed[key]!r} → {current[key]!r}")

    for key in missing:
        print(f"[claude-settings] {source} に {key} が無いので据え置き", file=sys.stderr)
    if not changed:
        print(f"[claude-settings] {managed_path} は {source} と一致しています")
        return 0
    try:
        write_atomic(managed_path, updated)
    except OSError as exc:
        print(f"[claude-settings] 書き込みに失敗: {exc}", file=sys.stderr)
        return 1
    print(f"[claude-settings] {managed_path} を更新しました:")
    for line in changed:
        print(f"  {line}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", type=pathlib.Path, help="ホストの settings.json")
    parser.add_argument(
        "--managed",
        type=pathlib.Path,
        default=DEFAULT_MANAGED,
        help="管理キーを持つ JSON (既定: configs/cli/claude/settings.remote.json)。"
        " nix store から呼ぶときは checkout が無いので明示する",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="書き込まず、反映漏れがあれば exit 1",
    )
    parser.add_argument(
        "--adopt",
        action="store_true",
        help="逆向き: target の現在値を管理ファイルへ取り込む"
        " (クライアント端末を正とする。管理キーの集合は増やさない)",
    )
    args = parser.parse_args()

    if args.adopt:
        return adopt(args.target, args.managed)

    try:
        managed = load_json(args.managed)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"[claude-settings] 管理ファイルを読めません: {exc}", file=sys.stderr)
        return 1
    if not managed:
        print(f"[claude-settings] {args.managed} が空です", file=sys.stderr)
        return 1

    try:
        target = load_json(args.target)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        # 壊れた JSON を上書きで握り潰さない (permissions を巻き添えにする)
        print(f"[claude-settings] {args.target} を読めません: {exc}", file=sys.stderr)
        return 1

    result = merged(target, managed)
    if result == target:
        return 0

    if args.check:
        stale = [k for k, v in managed.items() if target.get(k) != v]
        print(
            f"[claude-settings] {args.target} が古いキーを持っています: {', '.join(stale)}",
            file=sys.stderr,
        )
        return 1

    try:
        write_atomic(args.target, result)
    except OSError as exc:
        print(f"[claude-settings] 書き込みに失敗: {exc}", file=sys.stderr)
        return 1
    print(f"[claude-settings] {args.target} へ管理キーを反映しました")
    return 0


if __name__ == "__main__":
    sys.exit(main())
