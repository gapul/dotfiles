#!/usr/bin/env python3
"""Pre-run script for the soudan bot's weekly progress-slides cron job.

Hermes runs this on the host as hermes and puts its stdout in front of the job's prompt. It
gathers what the slides are written from:

  1. every message of the last week in the (IS-CPU6) Discord server, read with the bot token;
  2. the meeting minutes: HackMD notes linked in #meeting, fetched through /download (public);
  3. the GitHub digest that gapul's launchd agent writes (soudan-github-digest.ts), since only
     gapul can read the org's private repos.

Installed into $HERMES_HOME/scripts/ by nix-darwin activation (hosts/macmini.nix); Hermes
refuses scripts outside that directory.
"""

from __future__ import annotations

import datetime as dt
import json
import os
import re
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

GUILD = "1556901980042035340"
MEETING = "1559435621284446338"
PRESENTATION = "1559134355861803069"
# The team keeps its second core to itself for now: the slides go to the whole class. Nothing
# about it should reach the model, so it is cut here, before the prompt — #cpu2 is that core's
# channel, and anything else that names it is dropped by keyword. soudan-slides-publish.ts
# checks the finished slides against the same words before they are pushed.
SECRET_CHANNELS = {"1562094197119393872"}
SECRET = re.compile(
    r"2nd|２nd|second|セカンド|ヤバコア|SIMT|warp|ワープ|OoO|out.of.order|アウトオブオーダ"
    r"|スーパースカラ|superscalar|VLIW|GPU|アクセラレータ|ベクトル命令|ベクトル演算",
    re.I,
)
GITHUB_DIGEST = "/Users/gapul/.local/state/soudan-feed/github.md"
DAYS = 8
JST = dt.timezone(dt.timedelta(hours=9))
# 進捗報告3 was presented on Tue 2026-10-20; one report a week after that.
REPORT_BASE = (dt.date(2026, 10, 20), 3)
# A Discord API object (channel, message, user) as decoded from JSON.
ApiObject = dict[str, Any]


def bot_token() -> str:
    env = Path(os.environ.get("HERMES_HOME", Path.home() / ".hermes")) / ".env"
    m = re.search(r"^DISCORD_BOT_TOKEN=(.*)$", env.read_text(), re.M)
    return m.group(1).strip().strip("\"'")


TOKEN = bot_token()


def api(path: str) -> Any:
    """GET a Discord API path: the decoded JSON, or None where the bot may not look."""
    req = urllib.request.Request(
        "https://discord.com/api/v10" + path,
        headers={"Authorization": "Bot " + TOKEN, "User-Agent": "DiscordBot (soudan, 1)"},
    )
    for _ in range(5):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 429:
                time.sleep(float(json.load(e).get("retry_after", 1)) + 0.2)
                continue
            if e.code in (403, 404):
                return None
            raise
    raise RuntimeError("rate limited: " + path)


def drop_secret_lines(text: str) -> str:
    """Drop every line that names the second core, with the lines nested under it.

    Nesting is by indentation for list items and by level for markdown headings, which is how
    the HackMD minutes and the GitHub digest are laid out.
    """
    out: list[str] = []
    skip: tuple[str, int] | None = None  # ("indent", n) or ("heading", level)
    for line in text.splitlines():
        stripped = line.lstrip()
        heading = re.match(r"(#+)\s", stripped)
        indent = len(line) - len(stripped)
        if skip and stripped:
            kind, n = skip
            if kind == "heading" and not (heading and len(heading.group(1)) <= n):
                continue
            if kind == "indent" and indent > n:
                continue
            skip = None
        if SECRET.search(line):
            skip = ("heading", len(heading.group(1))) if heading else ("indent", indent)
            continue
        out.append(line)
    return "\n".join(out)


def snowflake(t: dt.datetime) -> str:
    return str((int(t.timestamp() * 1000) - 1420070400000) << 22)


def messages_since(channel: str, since: dt.datetime) -> list[ApiObject]:
    out: list[ApiObject] = []
    after = snowflake(since)
    while True:
        page: list[ApiObject] | None = api(f"/channels/{channel}/messages?limit=100&after={after}")
        if not page:
            break
        page.sort(key=lambda m: int(m["id"]))
        out.extend(page)
        after = page[-1]["id"]
        if len(page) < 100:
            break
    return out


def fmt(m: ApiObject) -> str:
    when = dt.datetime.fromisoformat(m["timestamp"]).astimezone(JST).strftime("%m/%d %H:%M")
    who = m["author"].get("global_name") or m["author"]["username"]
    text = m["content"]
    for u in m.get("mentions", []):
        name = u.get("global_name") or u["username"]
        text = text.replace(f"<@{u['id']}>", "@" + name).replace(f"<@!{u['id']}>", "@" + name)
    att = " ".join(f"[添付:{a['filename']}]" for a in m.get("attachments", []))
    return f"- {when} {who}: {text} {att}".rstrip()


def main() -> None:
    now = dt.datetime.now(JST)
    since = now - dt.timedelta(days=DAYS)

    days_ahead = (1 - now.weekday()) % 7 or 7  # the next Tuesday
    target = now.date() + dt.timedelta(days=days_ahead)
    number = REPORT_BASE[1] + (target - REPORT_BASE[0]).days // 7
    print(f"# 集計期間 {since:%Y-%m-%d %H:%M} 〜 {now:%Y-%m-%d %H:%M} JST")
    print(f"次の発表日(推定): {target:%Y-%m-%d}(火)、回数(推定): 進捗報告{number}")
    print()

    channels: list[ApiObject] = api(f"/guilds/{GUILD}/channels") or []
    by_id = {c["id"]: c for c in channels}
    active: ApiObject = api(f"/guilds/{GUILD}/threads/active") or {}
    threads: list[ApiObject] = active.get("threads", [])

    print("# Discord (IS-CPU6) の直近の発言")
    hackmd: list[str] = []
    for c in sorted(channels, key=lambda c: (c.get("parent_id") or "", c["position"])) + threads:
        if c["type"] not in (0, 5, 11, 12):
            continue
        if c["id"] in SECRET_CHANNELS or c.get("parent_id") in SECRET_CHANNELS:
            continue
        if SECRET.search(c["name"]):
            continue
        msgs = [
            m
            for m in messages_since(c["id"], since)
            if not m["author"].get("bot") and not SECRET.search(m["content"])
        ]
        if not msgs:
            continue
        parent = by_id.get(c.get("parent_id") or "", {}).get("name")
        label = f"#{c['name']}" if c["type"] in (0, 5) else f"#{parent} のスレッド「{c['name']}」"
        print(f"## {label}")
        for m in msgs:
            print(fmt(m))
            if c["id"] == MEETING:
                hackmd += re.findall(r"https://hackmd\.io/[^\s>)]+", m["content"])
        print()

    # Minutes are written ahead of the meeting, so the newest link may be older than the window.
    if not hackmd:
        recent: list[ApiObject] = api(f"/channels/{MEETING}/messages?limit=50") or []
        for m in recent:
            found = re.findall(r"https://hackmd\.io/[^\s>)]+", m["content"])
            if found:
                hackmd = found[:1]
                break
    print("# 議事録 (HackMD)")
    for url in dict.fromkeys(hackmd):
        base = re.sub(r"/(edit|publish|view)?([?#].*)?$", "", url)
        try:
            with urllib.request.urlopen(base + "/download", timeout=30) as r:
                body = r.read().decode("utf-8", "replace")
            print(f"## {base}")
            print(drop_secret_lines(body.strip())[:20000])
        except Exception as e:  # a private note just gets skipped
            print(f"## {base} (読めなかった: {e})")
        print()

    print("# 前回までの発表資料 (#presentation の PDF)")
    presented: list[ApiObject] = api(f"/channels/{PRESENTATION}/messages?limit=50") or []
    for m in presented:
        for a in m.get("attachments", []):
            if a["filename"].lower().endswith(".pdf"):
                print(f"- {m['timestamp'][:10]} {a['filename']}")
    print()

    print("# GitHub")
    try:
        p = Path(GITHUB_DIGEST)
        age = time.time() - p.stat().st_mtime
        if age > 3 * 86400:
            print(f"(注意: この要約は {age / 86400:.0f} 日前のもの)")
        print(drop_secret_lines(p.read_text())[:30000])
    except OSError as e:
        print(f"(GitHub の要約が読めなかった: {e})")


if __name__ == "__main__":
    main()
