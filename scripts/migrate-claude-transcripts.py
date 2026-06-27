#!/usr/bin/env python3
"""Claude の会話履歴 transcript ディレクトリ
(~/.config/claude/projects/<encoded-path>/) を、username/ディレクトリ移行後の
実在パスへリネームし、--resume/--continue で過去履歴が出るようにする。

- ディレクトリ名 = re.sub(r'[^A-Za-z0-9]', '-', 絶対パス)
- 旧パスは「中の jsonl の cwd フィールド」から取得(dir 名は不可逆なため)
  取れない場合のみ、dir 名末尾セグメントの basename 一意一致で補完
- 写像規則: /Users/yuki->/Users/gapul, ghq/github.com->Developer/github.com,
  それでも無ければ basename が ~/Developer/github.com 配下で一意一致するもの
- 複数の旧 dir が同一新 dir に集まる場合はファイル(UUID名)を移動してマージ
- 曖昧・不明は温存(履歴は消さない)。内部 jsonl の中身は履歴記録として変更しない。

使い方: python3 migrate-claude-transcripts.py        # ドライラン
        python3 migrate-claude-transcripts.py --apply # 実行(事前に tar バックアップ)
"""
import json, os, glob, re, sys, tarfile, shutil

APPLY = "--apply" in sys.argv
P = os.path.expanduser("~/.config/claude/projects")
ROOT = os.path.expanduser("~/Developer/github.com")

index = {}
for depth in ("*", "*/*", "*/*/*"):
    for p in glob.glob(os.path.join(ROOT, depth)):
        if os.path.isdir(p):
            index.setdefault(os.path.basename(p).lower(), set()).add(p)


def enc(path):
    return re.sub(r'[^A-Za-z0-9]', '-', path)


def map_path(cwd):
    if not cwd or not cwd.startswith("/Users/yuki"):
        return None
    n = cwd.replace("/Users/yuki", "/Users/gapul")
    n = n.replace("/Users/gapul/ghq/github.com", "/Users/gapul/Developer/github.com")
    if os.path.isdir(n):
        return n
    c = index.get(os.path.basename(n).lower())
    if c and len(c) == 1:
        return next(iter(c))
    return None


def find_cwd(d):
    # dir 内(再帰)の jsonl から最初に見つかる cwd
    for f in sorted(glob.glob(os.path.join(d, "**", "*.jsonl"), recursive=True)):
        try:
            for line in open(f, errors="ignore"):
                if '"cwd"' not in line:
                    continue
                try:
                    o = json.loads(line)
                except Exception:
                    continue
                if o.get("cwd"):
                    return o["cwd"]
        except Exception:
            pass
    return None


def from_dirname(d):
    # cwd が取れない時(memory のみ等)のフォールバック:
    # 「encode(repo basename) が dir 名のハイフン区切り接尾辞」かつ最長・一意一致
    base = os.path.basename(d)
    if not base.startswith("-Users-yuki"):
        return None
    low = base.lower()
    best = None  # (length, path)
    for bn, paths in index.items():
        if len(paths) != 1:
            continue
        suf = enc(bn).lower()  # bn は既に lower
        if low.endswith("-" + suf):
            if best is None or len(suf) > best[0]:
                best = (len(suf), next(iter(paths)))
    return best[1] if best else None


plan = []   # (src_dir, new_path, new_dir, via)
for d in sorted(glob.glob(os.path.join(P, "-Users-yuki*"))):
    if not os.path.isdir(d):
        continue
    cwd = find_cwd(d)
    via = "cwd"
    new = map_path(cwd)
    if not new:
        new = from_dirname(d)
        via = "dirname" if new else via
    if not new:
        plan.append((d, None, None, "SKIP"))
        continue
    plan.append((d, new, os.path.join(P, enc(new)), via))

# 表示
moves = [x for x in plan if x[1]]
skips = [x for x in plan if not x[1]]
for src, new, nd, via in moves:
    action = "MERGE" if os.path.exists(nd) else "RENAME"
    print(f"{action:7}[{via:7}] {os.path.basename(src)}\n         -> {os.path.basename(nd)}  ({new})")
for src, _, _, _ in skips:
    print(f"SKIP            {os.path.basename(src)}")
print(f"\n対象 {len(moves)} / 温存 {len(skips)}")

if not APPLY:
    print("\n(ドライラン。--apply で実行)")
    sys.exit(0)

# バックアップ(yuki dir 一式を tar)
bak = os.path.join(P, "_backup-yuki-transcripts.tar.gz")
with tarfile.open(bak, "w:gz") as tar:
    for src, _, _, _ in plan:
        tar.add(src, arcname=os.path.basename(src))
print(f"\nbackup: {bak}")

for src, new, nd, via in moves:
    if os.path.exists(nd):
        # マージ: src 内の全エントリを nd へ移動(UUID 名で衝突しない想定)
        for name in os.listdir(src):
            s = os.path.join(src, name)
            t = os.path.join(nd, name)
            if os.path.exists(t):
                base, ext = os.path.splitext(name)
                t = os.path.join(nd, f"{base}__from-yuki{ext}")
            shutil.move(s, t)
        os.rmdir(src)
        print(f"merged : {os.path.basename(src)} -> {os.path.basename(nd)}")
    else:
        os.rename(src, nd)
        print(f"renamed: {os.path.basename(src)} -> {os.path.basename(nd)}")
print("done")
