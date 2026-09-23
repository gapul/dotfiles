#!/usr/bin/env python3
"""Claude Code: the managed keys shipped to remotes (settings.remote.json) must equal what the
workstation's settings.json actually holds ("the client terminal is the source of truth",
configs/cli/claude/README.md). Shipping a key the workstation lacks creates "default on the
workstation, explicit on remotes" drift; that happened on 2026-08-13, hence this check.

The workstation file is a symlink into gapul/ai-agent-state, which is not in this repository.
Where the link is dangling (CI checkout, a store copy) there is nothing to compare, so skip.
"""
import json
import sys
from pathlib import Path

CLAUDE = Path(__file__).resolve().parent.parent / "configs" / "cli" / "claude"


def drift(managed, source, prefix=""):
    """Walk the managed file's shape and collect leaf paths that differ on the workstation.
    Descend only when both sides are objects, the same promise merge-claude-settings.py's
    deep_merge makes (permissions manages only defaultMode; allow is left to each side)."""
    out = []
    for name, value in managed.items():
        path = prefix + name
        if name == "$schema":
            continue
        if name not in source:
            out.append(f"{path} (母艦の settings.json に無い)")
        elif isinstance(value, dict) and isinstance(source[name], dict):
            out.extend(drift(value, source[name], path + "."))
        elif value != source[name]:
            out.append(path)
    return out


def main():
    workstation = CLAUDE / "settings.json"
    if not workstation.exists():
        print(f"claude: {workstation} が読めない (ai-agent-state が無い環境) のでスキップ")
        return 0
    managed = json.loads((CLAUDE / "settings.remote.json").read_text())
    drifted = drift(managed, json.loads(workstation.read_text()))
    if drifted:
        print("claude: settings.remote.json の管理キーが母艦の settings.json と食い違う:", file=sys.stderr)
        for d in drifted:
            print(f"  {d}", file=sys.stderr)
        return 1
    print("claude: managed settings match the workstation")
    return 0


if __name__ == "__main__":
    if "--demo" in sys.argv:
        assert drift({"a": 1, "b": {"c": 2}}, {"a": 1, "b": {"c": 2}}) == []
        assert drift({"a": 1}, {}) == ["a (母艦の settings.json に無い)"]
        assert drift({"b": {"c": 2}}, {"b": {"c": 3}}) == ["b.c"]
        assert drift({"$schema": "x", "b": {"c": 2}}, {"b": 5}) == ["b"]
        print("demo ok")
        sys.exit(0)
    sys.exit(main())
