#!/usr/bin/env python3
"""Push the soudan bot's weekly slide draft into the IS-CPU-6/slides repository.

Runs as gapul (nix/home/macmini-soudan-digest.nix) after the bot's Monday cron job, because the
org has deploy keys disabled and gapul's gh login is the only write access there is; the bot
never holds it. The files come from the hsoudan sandbox, which strangers can drive, so they
are read without following symlinks and checked for the second-core words before anything
is committed (the same list as in soudan-weekly-collect.py).

Usage: soudan-slides-publish.py [--final]
  --final: the last attempt of the evening; a missing draft is reported instead of ignored.
"""

import datetime as dt
import os
import re
import shutil
import stat
import subprocess
import sys
import urllib.request
from pathlib import Path

SRC_ROOT = "/Users/hsoudan/workspace/progress"
REPO = Path.home() / ".local/share/soudan-slides"
REMOTE = "https://github.com/IS-CPU-6/slides.git"
JST = dt.timezone(dt.timedelta(hours=9))
LIMITS = {".md": 512 * 1024, ".pdf": 50 * 1024 * 1024}
SECRET = re.compile(
    r"2nd|２nd|second|セカンド|ヤバコア|SIMT|warp|ワープ|OoO|out.of.order|アウトオブオーダ"
    r"|スーパースカラ|superscalar|VLIW|GPU|アクセラレータ|ベクトル命令|ベクトル演算",
    re.I,
)
GIT = [
    "git",
    "-c",
    "credential.helper=",
    "-c",
    "credential.helper=!gh auth git-credential",
    "-c",
    "commit.gpgsign=false",
    "-c",
    "user.name=soudan bot",
    "-c",
    "user.email=soudan-bot@users.noreply.github.com",
]


def notify(title, body):
    try:
        url = (Path.home() / ".config/ntfy/url").read_text().strip()
        token = (Path.home() / ".config/ntfy/token").read_text().strip()
    except OSError:
        return
    req = urllib.request.Request(
        url,
        data=body.encode(),
        headers={"Authorization": "Bearer " + token, "Title": title, "Tags": "cpuex"},
    )
    try:
        urllib.request.urlopen(req, timeout=15).read()
    except Exception:
        pass


def fail(msg):
    print(msg, file=sys.stderr)
    notify("進捗スライドを slides repo に上げられない", msg)
    sys.exit(1)


def read_plain(path, limit):
    """Read a regular file without following a symlink at any step below SRC_ROOT."""
    rel = Path(path).relative_to(SRC_ROOT)
    cur = Path(SRC_ROOT)
    for part in rel.parts[:-1]:
        cur = cur / part
        if not stat.S_ISDIR(os.lstat(cur).st_mode):
            raise ValueError(f"{cur} is not a plain directory")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "rb") as f:
        st = os.fstat(f.fileno())
        if not stat.S_ISREG(st.st_mode):
            raise ValueError(f"{path} is not a regular file")
        if st.st_size > limit:
            raise ValueError(f"{path} is larger than {limit} bytes")
        return f.read()


def main():
    final = "--final" in sys.argv
    now = dt.datetime.now(JST)
    target = now.date() + dt.timedelta(days=(1 - now.weekday()) % 7 or 7)
    src = Path(SRC_ROOT) / target.isoformat()

    try:
        names = sorted(
            n for n in os.listdir(src) if re.fullmatch(r"progress-\d+\.(md|pdf)", n)
        )
    except OSError:
        names = []
    if not any(n.endswith(".md") for n in names):
        if final:
            fail(f"{src} に下書きの md が無い(bot の cron が失敗した?)")
        return

    files = {}
    for n in names:
        try:
            files[n] = read_plain(src / n, LIMITS[Path(n).suffix])
        except (OSError, ValueError) as e:
            fail(f"{n} を読めない: {e}")

    for n, data in files.items():
        text = data.decode("utf-8", "replace")
        if n.endswith(".pdf"):
            pdftotext = shutil.which("pdftotext")
            if not pdftotext:
                fail("pdftotext が無いので PDF を確認できない")
            text = subprocess.run(
                [pdftotext, "-", "-"], input=data, capture_output=True, check=True
            ).stdout.decode("utf-8", "replace")
        hit = SECRET.search(text)
        if hit:
            fail(f"{n} に 2nd コア関連の語「{hit.group(0)}」がある。repo には上げていない。")

    if not (REPO / ".git").is_dir():
        subprocess.run([*GIT, "clone", "-q", REMOTE, str(REPO)], check=True)
    git = [*GIT, "-C", str(REPO)]
    subprocess.run([*git, "pull", "-q", "--ff-only"], check=True)
    dst = REPO / "progress" / target.isoformat()
    dst.mkdir(parents=True, exist_ok=True)
    for n, data in files.items():
        (dst / n).write_bytes(data)
    subprocess.run([*git, "add", "progress"], check=True)
    if subprocess.run([*git, "diff", "--cached", "--quiet"]).returncode == 0:
        return
    subprocess.run(
        [*git, "commit", "-q", "-m", f"progress {target.isoformat()}: soudan bot の下書き"],
        check=True,
    )
    subprocess.run([*git, "push", "-q", "origin", "HEAD"], check=True)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as e:
        fail(f"git が失敗した: {e}")
