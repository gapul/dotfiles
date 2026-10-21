#!/usr/bin/env python3
"""Write a markdown digest of the last week's activity in the IS-CPU-6 GitHub org.

Runs as gapul (launchd agent, nix/home/macmini-soudan-digest.nix) because gapul's gh login is
the only one with access to the org's private repos. The soudan bot's weekly-slides cron job
reads the file it writes; the token itself never reaches hermes or the hsoudan sandbox.

Usage: soudan-github-digest.py OUTPUT [DAYS]
"""

import datetime as dt
import json
import os
import subprocess
import sys

ORG = "IS-CPU-6"
JST = dt.timezone(dt.timedelta(hours=9))


def gh(path):
    out = subprocess.run(
        ["gh", "api", "--paginate", "--slurp", path],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    pages = json.loads(out)
    items = []
    for page in pages:
        items.extend(page if isinstance(page, list) else [page])
    return items


def jst(stamp):
    return (
        dt.datetime.fromisoformat(stamp.replace("Z", "+00:00"))
        .astimezone(JST)
        .strftime("%m/%d %H:%M")
    )


def main():
    out_path = sys.argv[1]
    days = int(sys.argv[2]) if len(sys.argv) > 2 else 8
    since = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=days)
    since_s = since.strftime("%Y-%m-%dT%H:%M:%SZ")

    lines = [
        f"# GitHub {ORG}: activity since {since.astimezone(JST):%Y-%m-%d %H:%M} JST",
        "",
    ]
    for repo in sorted(gh(f"orgs/{ORG}/repos?per_page=100"), key=lambda r: r["name"]):
        name = repo["name"]
        if repo.get("archived") or repo["pushed_at"] < since_s:
            continue
        section = []

        # Commits on every branch, not just the default one: work lands on personal branches
        # (e.g. 261018_ashitani) and is merged later.
        seen = {}
        for br in gh(f"repos/{ORG}/{name}/branches?per_page=100"):
            try:
                commits = gh(
                    f"repos/{ORG}/{name}/commits?sha={br['name']}&since={since_s}&per_page=100"
                )
            except subprocess.CalledProcessError:
                continue
            for c in commits:
                if c["sha"] in seen:
                    continue
                author = (c.get("author") or {}).get("login") or c["commit"]["author"][
                    "name"
                ]
                seen[c["sha"]] = (
                    c["commit"]["author"]["date"],
                    br["name"],
                    author,
                    c["commit"]["message"].splitlines()[0][:160],
                )
        if seen:
            section.append(f"### commits ({len(seen)})")
            for date, branch, author, msg in sorted(seen.values()):
                section.append(f"- {jst(date)} [{branch}] {author}: {msg}")

        prs = [
            p
            for p in gh(
                f"repos/{ORG}/{name}/pulls?state=all&sort=updated&direction=desc&per_page=50"
            )
            if p["updated_at"] >= since_s
        ]
        if prs:
            section.append("### pull requests")
            for p in prs:
                state = "merged" if p.get("merged_at") else p["state"]
                section.append(
                    f"- #{p['number']} {state} {p['user']['login']}: {p['title']}"
                    f" ({p['head']['ref']} -> {p['base']['ref']})"
                )

        issues = [
            i
            for i in gh(f"repos/{ORG}/{name}/issues?state=all&since={since_s}&per_page=50")
            if "pull_request" not in i
        ]
        if issues:
            section.append("### issues")
            for i in issues:
                section.append(
                    f"- #{i['number']} {i['state']} {i['user']['login']}: {i['title']}"
                )

        if section:
            lines.append(f"## {name}")
            lines.extend(section)
            lines.append("")

    tmp = out_path + ".tmp"
    with open(tmp, "w") as f:
        f.write("\n".join(lines) + "\n")
    os.replace(tmp, out_path)


if __name__ == "__main__":
    main()
