#!/usr/bin/env python3
"""username/ディレクトリ移行に伴い ~/.config/claude/.claude.json の
projects キー(旧レイアウト)を実在する ~/Developer/github.com/... へ再マップする。

マッピング規則(誤対応を避け、確実なものだけ):
  1. ghq/github.com -> Developer/github.com (決定的)
  2. すでに実在するキーはそのまま
  3. basename が Developer/github.com 配下で「一意」に一致するものだけ採用
  4. 上記に該当しない曖昧キーは温存(履歴は消さない)

衝突(複数の旧キー -> 同一実ディレクトリ)は history をマージ。
Claude Code 終了状態での実行を推奨(稼働中は保存で上書きされ得る)。
"""
import json, os, glob, shutil, sys

F = os.path.expanduser("~/.config/claude/.claude.json")
ROOT = os.path.expanduser("~/Developer/github.com")

data = json.load(open(F))
proj = data.get("projects", {})

# basename(lower) -> set(paths)
index = {}
for depth in ("*", "*/*", "*/*/*"):
    for p in glob.glob(os.path.join(ROOT, depth)):
        if os.path.isdir(p):
            index.setdefault(os.path.basename(p).lower(), set()).add(p)


def target_for(k):
    if os.path.isdir(k):
        return k  # 既に実在
    n = k.replace("/Users/gapul/ghq/github.com", "/Users/gapul/Developer/github.com")
    if os.path.isdir(n):
        return n
    cands = index.get(os.path.basename(k).lower())
    if cands and len(cands) == 1:
        return next(iter(cands))
    return None  # 曖昧 -> 温存


def merge(objs):
    """project obj を history マージしつつ統合。history が最長のものを基点に。"""
    objs = [o for o in objs if isinstance(o, dict)]
    if not objs:
        return {}
    base = max(objs, key=lambda o: len(o.get("history", []) or []))
    merged = dict(base)
    seen = {json.dumps(h, sort_keys=True, ensure_ascii=False) for h in merged.get("history", []) or []}
    for o in objs:
        if o is base:
            continue
        for h in o.get("history", []) or []:
            key = json.dumps(h, sort_keys=True, ensure_ascii=False)
            if key not in seen:
                seen.add(key)
                merged.setdefault("history", []).append(h)
    return merged


# 旧キー -> ターゲット を決定し、ターゲット毎に集約
groups = {}   # target -> [source_keys]
remap = {}    # source -> target (実際に動かすものだけ)
for k in list(proj):
    t = target_for(k)
    if t is None or t == k:
        continue
    remap[k] = t
    groups.setdefault(t, []).append(k)

if not remap:
    print("変更対象なし")
    sys.exit(0)

bak = F + ".bak-projects-migration"
shutil.copy2(F, bak)

for tgt, srcs in groups.items():
    objs = [proj[s] for s in srcs]
    if tgt in proj:
        objs.append(proj[tgt])
    proj[tgt] = merge(objs)
    for s in srcs:
        if s != tgt:
            proj.pop(s, None)

# 原子的に書き戻し
tmp = F + ".tmp"
with open(tmp, "w") as fh:
    json.dump(data, fh, ensure_ascii=False, indent=2)
json.load(open(tmp))  # 妥当性確認
os.replace(tmp, F)

print(f"backup: {bak}")
print(f"remapped {len(remap)} keys -> {len(groups)} dirs")
for s, t in sorted(remap.items()):
    print(f"  {s}\n   -> {t}")
