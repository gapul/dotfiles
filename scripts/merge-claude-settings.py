#!/usr/bin/env python3
"""Merge the dotfiles-managed Claude Code settings into a host's settings.json.

nssh 先の ~/.claude/settings.json はホスト所有のファイル。gh / codex のように symlink で
丸ごと差し替えると、nssh の `reset --hard` でホスト固有の値が毎回消える。そこで
リポジトリが持つ管理キーだけを既存の JSON へ上書き merge する。~/.bashrc に
bashrc.remote を読む行だけ足すのと同じ考え方で、管理外のキーはホスト側に残す。

merge は入れ子まで潜る。permissions は defaultMode だけを配りたいので、丸ごと置き換えると
ホストが育てた allow / additionalDirectories を巻き添えにするため (deep_merge 参照)。
管理対象・管理外の一覧は configs/cli/claude/README.md にある。

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


def deep_merge(target: dict, managed: dict) -> dict:
    """Overlay the managed keys onto the target, recursing into nested objects.

    両側が object のキーだけ再帰する。これが要るのは permissions で、管理したいのは
    defaultMode だけなのに、丸ごと置き換えるとホストが育てた allow /
    additionalDirectories まで消えてしまうため。
    配列は再帰しない (allow を要素ごとに混ぜたいわけではない)。
    """
    out = dict(target)
    for key, value in managed.items():
        current = out.get(key)
        if isinstance(value, dict) and isinstance(current, dict):
            out[key] = deep_merge(current, value)
        else:
            out[key] = value
    return out


def merged(target: dict, managed: dict) -> dict:
    """deep_merge に $schema の並べ替えを足したもの (トップレベル専用)。

    $schema は Claude Code が読む値ではなくエディタ補完用なので、既存ファイルが
    持っていなければ先頭に置く (手で開いたときに素性が分かるように)。
    """
    out = deep_merge(target, managed)
    if "$schema" in out:
        out = {"$schema": out.pop("$schema"), **out}
    return out


def stale_paths(target: dict, managed: dict, prefix: str = "") -> list[str]:
    """反映漏れしている管理キーを a.b.c 形式で並べる (--check の表示用)。

    トップレベルの比較だけだと、permissions のように一部のサブキーだけ管理している
    ものが「ホスト側に allow がある」というだけで毎回 stale に見えてしまう。
    """
    out: list[str] = []
    for key, value in managed.items():
        if key == "$schema":
            continue
        path = f"{prefix}{key}"
        current = target.get(key) if isinstance(target, dict) else None
        if isinstance(value, dict) and isinstance(current, dict):
            out.extend(stale_paths(current, value, f"{path}."))
        elif current != value:
            out.append(path)
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


def adopt_tree(
    managed: dict, current: dict, prefix: str = ""
) -> tuple[dict, list[str], list[str]]:
    """管理ファイルの構造をなぞって、ホスト側の現在値へ差し替えた木を返す。

    管理キーの集合は増やさない。managed に無いキーは見に行かないので、
    permissions.allow のようなホスト所有の値を巻き込むことがない。
    戻り値は (更新後の木, 変わったパスの説明, ホスト側に無かったパス)。
    """
    updated = dict(managed)
    changed: list[str] = []
    missing: list[str] = []
    for key, value in managed.items():
        if key == "$schema":
            continue
        path = f"{prefix}{key}"
        if not isinstance(current, dict) or key not in current:
            missing.append(path)
            continue
        source_value = current[key]
        if isinstance(value, dict) and isinstance(source_value, dict):
            sub, sub_changed, sub_missing = adopt_tree(value, source_value, f"{path}.")
            updated[key] = sub
            changed.extend(sub_changed)
            missing.extend(sub_missing)
        elif source_value != value:
            updated[key] = source_value
            changed.append(f"{path}: {value!r} → {source_value!r}")
    return updated, changed, missing


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

    updated, changed, missing = adopt_tree(managed, current)

    for key in missing:
        print(
            f"[claude-settings] {source} に {key} が無いので据え置き", file=sys.stderr
        )
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
        stale = stale_paths(target, managed)
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
