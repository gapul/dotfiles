#!/usr/bin/env python3
"""Keep a Forgejo pull mirror of every GitHub repository owned by GITHUB_OWNER.

Creates a mirror for each owned GitHub repo that Forgejo does not have yet. Forgejo itself
re-fetches existing mirrors on its own interval, so this only has to notice new repos. Repos
deleted on GitHub keep their mirror: surviving that is the point.

Environment: GITHUB_TOKEN (fine-grained, Contents + Metadata read on all repos), FORGEJO_TOKEN,
FORGEJO_URL (default http://127.0.0.1:3003), GITHUB_OWNER / FORGEJO_OWNER (default gapul).
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

GH_TOKEN = os.environ["GITHUB_TOKEN"]
FJ_TOKEN = os.environ["FORGEJO_TOKEN"]
FJ_URL = os.environ.get("FORGEJO_URL", "http://127.0.0.1:3003").rstrip("/")
GH_OWNER = os.environ.get("GITHUB_OWNER", "gapul")
FJ_OWNER = os.environ.get("FORGEJO_OWNER", "gapul")


def call(url: str, auth: str, body: dict | None = None):
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body else None,
                                 method="POST" if body else "GET",
                                 headers={"Authorization": auth, "Accept": "application/json",
                                          "Content-Type": "application/json", "User-Agent": "github-mirror"})
    with urllib.request.urlopen(req, timeout=600) as r:
        return json.load(r)


def github_repos() -> list[dict]:
    repos, page = [], 1
    while True:
        batch = call(f"https://api.github.com/user/repos?per_page=100&affiliation=owner&page={page}",
                     f"Bearer {GH_TOKEN}")
        repos += [r for r in batch if r["owner"]["login"] == GH_OWNER]
        if len(batch) < 100:
            return repos
        page += 1


def forgejo_names() -> set[str]:
    names, page = set(), 1
    while True:
        batch = call(f"{FJ_URL}/api/v1/user/repos?limit=50&page={page}", f"token {FJ_TOKEN}")
        names |= {r["name"].lower() for r in batch if r["owner"]["login"] == FJ_OWNER}
        if len(batch) < 50:
            return names
        page += 1


def main() -> int:
    have = forgejo_names()
    missing = [r for r in github_repos() if r["name"].lower() not in have]
    failed = 0
    for r in missing:
        try:
            call(f"{FJ_URL}/api/v1/repos/migrate", f"token {FJ_TOKEN}", {
                "clone_addr": r["clone_url"], "auth_token": GH_TOKEN, "service": "git",
                "mirror": True, "mirror_interval": "8h", "private": True,
                "repo_owner": FJ_OWNER, "repo_name": r["name"],
                "description": (r.get("description") or "")[:255],
            })
            print(f"mirrored {r['full_name']}", flush=True)
        except urllib.error.HTTPError as e:
            failed += 1
            print(f"FAILED {r['full_name']}: {e.code} {e.read()[:300]!r}", file=sys.stderr, flush=True)
    print(f"{len(missing) - failed} new mirrors, {failed} failed, {len(have)} already present")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
