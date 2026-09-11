#!/usr/bin/env python3
"""Discover limited freebies and ingest downloaded assets into git-annex.

The network side is intentionally data-only. It never runs installers or scripts and
never guesses its way through a checkout. Account actions remain in the claim queue;
files downloaded into the server inbox are organized and archived automatically.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import html
import json
import os
import re
import shutil
import sqlite3
import subprocess
import tarfile
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

UA = "freebie-collector/1.0 (+personal archival)"
POSITIVE = (
    "limited time free", "free for a limited", "temporarily free", "100% off",
    "free until", "free through", "期間限定無料", "期間限定で無料", "無償配布",
    "今だけ無料", "無料配布",
)
NEGATIVE = (
    "free trial", "trial version", "demo version", "free weekend", "体験版",
    "無料体験", "フリーウィークエンド", "subscription required",
)
ASSET_WORDS = {
    "font": "fonts/free", "typeface": "fonts/free", "フォント": "fonts/free",
    "sample pack": "audio/sample-packs", "サンプルパック": "audio/sample-packs",
    "kontakt": "audio/instruments", "instrument": "audio/instruments", "音源": "audio/instruments",
    "plugin": "audio/plugins", "plug-in": "audio/plugins", "vst": "audio/plugins", "プラグイン": "audio/plugins",
    "sound effect": "audio/sfx", "sfx": "audio/sfx", "効果音": "audio/sfx",
    "brush": "graphics/brushes", "ブラシ": "graphics/brushes",
    "texture": "textures", "テクスチャ": "textures",
    "lut": "video/luts", "template": "templates", "テンプレート": "templates",
    "3d model": "3d/models", "3d asset": "3d/models", "3dモデル": "3d/models",
}
ARCHIVES = {".zip", ".tar", ".tgz", ".gz", ".bz2", ".xz"}
NO_ANNEX = {"README.md", "offer.json", "LICENSE", "LICENSE.txt", "OFL.txt"}


def now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc).astimezone()


def fetch(url: str, timeout: int = 30) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/rss+xml, application/atom+xml, text/xml, */*"})
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.read(8 * 1024 * 1024)


def text_of(node: ET.Element | None) -> str:
    if node is None:
        return ""
    return "".join(node.itertext()).strip()


def feed_items(data: bytes) -> list[dict[str, str]]:
    root = ET.fromstring(data)
    result: list[dict[str, str]] = []
    nodes = root.findall(".//item")
    if not nodes:
        nodes = root.findall(".//{http://www.w3.org/2005/Atom}entry")
    for node in nodes[:80]:
        title = text_of(node.find("title")) or text_of(node.find("{*}title"))
        link = text_of(node.find("link"))
        if not link:
            link_node = node.find("{*}link")
            link = (link_node.attrib.get("href", "") if link_node is not None else "")
        body = text_of(node.find("description")) or text_of(node.find("{*}summary")) or text_of(node.find("{*}content"))
        published = text_of(node.find("pubDate")) or text_of(node.find("{*}published")) or text_of(node.find("{*}updated"))
        result.append({"title": html.unescape(title), "url": link, "summary": html.unescape(re.sub(r"<[^>]+>", " ", body)), "published": published})
    return result


def category_for(value: str) -> str:
    folded = value.casefold()
    for word, category in ASSET_WORDS.items():
        if word in folded:
            return category
    return "misc"


def qualifies(value: str) -> bool:
    folded = re.sub(r"\s+", " ", value.casefold())
    return any(word in folded for word in POSITIVE) and not any(word in folded for word in NEGATIVE)


def stable_id(url: str) -> str:
    clean = urllib.parse.urlsplit(url)._replace(fragment="").geturl()
    return hashlib.sha256(clean.encode()).hexdigest()[:20]


def db_open(path: Path) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(path)
    db.execute("""CREATE TABLE IF NOT EXISTS offers (
        id TEXT PRIMARY KEY, title TEXT NOT NULL, url TEXT NOT NULL, source TEXT,
        category TEXT NOT NULL, discovered TEXT NOT NULL, published TEXT,
        deadline TEXT, status TEXT NOT NULL DEFAULT 'claim-required', details TEXT NOT NULL
    )""")
    db.commit()
    return db


def store_offer(db: sqlite3.Connection, item: dict[str, object]) -> bool:
    oid = stable_id(str(item["url"]))
    exists = db.execute("SELECT 1 FROM offers WHERE id=?", (oid,)).fetchone() is not None
    db.execute("""INSERT INTO offers(id,title,url,source,category,discovered,published,deadline,status,details)
        VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET
        title=excluded.title, category=excluded.category, deadline=COALESCE(excluded.deadline,offers.deadline), details=excluded.details""",
        (oid, item["title"], item["url"], item.get("source", "seed"), item.get("category", "misc"),
         item.get("discovered", now().isoformat()), item.get("published", ""), item.get("deadline"),
         item.get("status", "claim-required"), json.dumps(item, ensure_ascii=False, sort_keys=True)))
    return not exists


def scan(config: dict, db: sqlite3.Connection) -> tuple[int, list[str]]:
    added = 0
    errors: list[str] = []
    excluded = tuple(config.get("excluded_hosts", []))
    for item in config.get("seed_offers", []):
        added += int(store_offer(db, dict(item)))
    for source in config.get("feeds", []):
        try:
            for item in feed_items(fetch(source["url"])):
                if not item["url"] or urllib.parse.urlsplit(item["url"]).hostname in excluded:
                    continue
                combined = f"{item['title']} {item['summary']}"
                if not qualifies(combined):
                    continue
                item.update(source=source["name"], category=category_for(combined), discovered=now().isoformat())
                added += int(store_offer(db, item))
        except Exception as exc:  # one broken feed must not suppress the other sources
            errors.append(f"{source['name']}: {exc}")
    db.commit()
    return added, errors


def safe_name(value: str) -> str:
    value = re.sub(r"[^0-9A-Za-z._+\-ぁ-んァ-ヶ一-龠]+", "-", value).strip("-.")
    return value[:100] or "unnamed"


def run(cmd: list[str], cwd: Path, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=check)


def safe_extract(archive: Path, target: Path) -> None:
    target.mkdir(parents=True, exist_ok=True)
    if archive.suffix.casefold() == ".zip":
        with zipfile.ZipFile(archive) as zf:
            for info in zf.infolist():
                dest = (target / info.filename).resolve()
                if target.resolve() not in dest.parents and dest != target.resolve():
                    raise ValueError(f"unsafe archive member: {info.filename}")
                if (info.external_attr >> 16) & 0o170000 == 0o120000:
                    raise ValueError(f"archive symlink rejected: {info.filename}")
            zf.extractall(target)
    elif tarfile.is_tarfile(archive):
        with tarfile.open(archive) as tf:
            for member in tf.getmembers():
                dest = (target / member.name).resolve()
                if target.resolve() not in dest.parents and dest != target.resolve():
                    raise ValueError(f"unsafe archive member: {member.name}")
                if member.issym() or member.islnk():
                    raise ValueError(f"archive link rejected: {member.name}")
            tf.extractall(target, filter="data")


def metadata_args(meta: dict[str, object]) -> list[str]:
    pairs = {
        "offer-type": meta.get("offer_type", "limited-time-free"),
        "acquired-price": meta.get("acquired_price", "0"),
        "acquired": meta.get("acquired", now().date().isoformat()),
        "source": meta.get("source"), "vendor": meta.get("vendor"),
        "announced-until": meta.get("deadline"),
        "asset-type": meta.get("asset_type") or str(meta.get("category", "misc")).split("/")[-1],
        "license": meta.get("license"), "platform": meta.get("platform"),
    }
    args: list[str] = []
    for key, value in pairs.items():
        if value:
            args.extend(["--set", f"{key}={value}"])
    return args


def ingest_one(manifest: Path, repo: Path, db: sqlite3.Connection) -> Path:
    meta = json.loads(manifest.read_text())
    payload = (manifest.parent / meta["file"]).resolve()
    if not payload.is_file() or manifest.parent.resolve() not in payload.parents:
        raise ValueError(f"invalid payload in {manifest}")
    category = str(meta.get("category") or category_for(f"{meta.get('title', '')} {payload.name}"))
    vendor = safe_name(str(meta.get("vendor", "unknown")))
    product = safe_name(str(meta.get("title", payload.stem)))
    dest = repo / category / vendor / product
    if dest.exists():
        dest = dest.with_name(f"{dest.name}-{now().strftime('%Y%m%d-%H%M%S')}")
    original = dest / "original"
    original.mkdir(parents=True)
    moved = original / payload.name
    shutil.move(payload, moved)
    shutil.copy2(manifest, dest / "offer.json")
    if meta.get("source"):
        try:
            (dest / "offer-page.html").write_bytes(fetch(str(meta["source"])))
        except Exception:
            pass
    if moved.suffix.casefold() in ARCHIVES or tarfile.is_tarfile(moved):
        safe_extract(moved, dest / "files")
    run(["git", "add", str(dest / "offer.json")], repo)
    annexed = [p for p in dest.rglob("*") if p.is_file() and p.name not in NO_ANNEX]
    if annexed:
        run(["git", "annex", "add", "--"] + [str(p) for p in annexed], repo)
        for path in annexed:
            run(["git", "annex", "metadata", *metadata_args(meta), "--", str(path)], repo)
    run(["git", "commit", "-m", f"期間限定無料素材を追加: {meta.get('title', product)}"], repo)
    if meta.get("source"):
        db.execute("UPDATE offers SET status='acquired' WHERE id=?", (stable_id(meta["source"]),))
        db.commit()
    manifest.unlink()
    return dest


def ingest(inbox: Path, repo: Path, db: sqlite3.Connection) -> tuple[list[Path], list[str]]:
    done: list[Path] = []
    errors: list[str] = []
    for manifest in sorted(inbox.glob("*.freebie.json")):
        try:
            done.append(ingest_one(manifest, repo, db))
        except Exception as exc:
            errors.append(f"{manifest.name}: {exc}")
    if done:
        result = run(["git", "annex", "sync", "--content"], repo, check=False)
        if result.returncode:
            errors.append("git-annex sync: " + result.stdout[-1000:])
    return done, errors


def prepare_unmanaged_downloads(inbox: Path) -> None:
    """Create a minimal manifest for files dropped into the dedicated inbox.

    macOS normally preserves the source URL in Spotlight metadata. Failure to read
    it is harmless: the file remains in the inbox instead of losing provenance.
    """
    mdls = shutil.which("mdls")
    if not mdls:
        return
    manifested = set()
    for manifest in inbox.glob("*.freebie.json"):
        try:
            manifested.add(json.loads(manifest.read_text()).get("file"))
        except Exception:
            continue
    for payload in inbox.iterdir():
        if not payload.is_file() or payload.name.endswith(".freebie.json") or payload.name in manifested:
            continue
        result = subprocess.run([mdls, "-raw", "-name", "kMDItemWhereFroms", str(payload)],
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        urls = re.findall(r'https?://[^"\\s)]+', result.stdout)
        if not urls:
            continue
        source = urls[0].replace('\\U0026', '&')
        host = urllib.parse.urlsplit(source).hostname or "unknown"
        meta = {
            "file": payload.name, "title": payload.stem, "vendor": host,
            "source": source, "category": category_for(payload.name),
            "offer_type": "limited-time-free", "acquired_price": "0",
        }
        (inbox / f"{payload.name}.freebie.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n")


def download_declared(config: dict, inbox: Path, db: sqlite3.Connection) -> tuple[int, list[str]]:
    """Download only explicitly declared URLs; no link following or execution."""
    downloaded = 0
    errors: list[str] = []
    for entry in config.get("direct_downloads", []):
        url = str(entry["url"])
        oid = stable_id(str(entry.get("source", url)))
        row = db.execute("SELECT status FROM offers WHERE id=?", (oid,)).fetchone()
        if row and row[0] == "acquired":
            continue
        filename = safe_name(str(entry.get("filename") or Path(urllib.parse.urlsplit(url).path).name or f"{oid}.download"))
        payload = inbox / filename
        manifest = inbox / f"{filename}.freebie.json"
        if payload.exists() and manifest.exists():
            continue
        try:
            payload.write_bytes(fetch(url))
            meta = dict(entry)
            meta.update(file=filename, source=entry.get("source", url), acquired=now().date().isoformat())
            manifest.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n")
            downloaded += 1
        except Exception as exc:
            payload.unlink(missing_ok=True)
            errors.append(f"direct download {url}: {exc}")
    return downloaded, errors


def export_queue(db: sqlite3.Connection, output: Path) -> int:
    current = now()
    for oid, deadline, discovered in db.execute(
        "SELECT id,deadline,discovered FROM offers WHERE status='claim-required'"
    ).fetchall():
        try:
            if deadline and dt.datetime.fromisoformat(deadline) < current:
                db.execute("UPDATE offers SET status='expired' WHERE id=?", (oid,))
            elif not deadline and dt.datetime.fromisoformat(discovered) < current - dt.timedelta(days=14):
                db.execute("UPDATE offers SET status='stale' WHERE id=?", (oid,))
        except ValueError:
            continue
    db.commit()
    rows = db.execute("""SELECT title,url,source,category,deadline,status,details FROM offers
        WHERE status = 'claim-required'
        ORDER BY CASE WHEN deadline IS NULL THEN 1 ELSE 0 END, deadline, discovered DESC""").fetchall()
    stamp = now().isoformat(timespec="seconds")
    lines = ["# Limited-time free claim queue", "", f"Updated: {stamp}", "",
             "Automatically discovered offers. A zero-price checkout, login, CAPTCHA, or license consent still needs a site adapter or human confirmation.", ""]
    for title, url, source, category, deadline, status, details in rows:
        extra = json.loads(details)
        suffix = f" — deadline `{deadline}`" if deadline else ""
        coupon = f" — coupon `{extra['coupon']}`" if extra.get("coupon") else ""
        lines.extend([f"- [{title}]({url}) — `{category}` — {source}{suffix}{coupon}", ""])
    content = "\n".join(lines)
    output.parent.mkdir(parents=True, exist_ok=True)
    if not output.exists() or output.read_text() != content:
        output.write_text(content)
    return len(rows)


def notify(message: str) -> None:
    base = Path.home() / ".config/ntfy"
    if not (base / "url").is_file() or not (base / "token").is_file():
        return
    req = urllib.request.Request((base / "url").read_text().strip(), data=message.encode(), method="POST",
        headers={"Authorization": "Bearer " + (base / "token").read_text().strip(), "Title": "limited freebies", "Tags": "package"})
    try:
        urllib.request.urlopen(req, timeout=15).read()
    except Exception:
        pass


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("scan", "ingest", "report", "run"), nargs="?", default="run")
    parser.add_argument("--config", type=Path, default=Path.home() / ".config/freebie-collector/sources.json")
    parser.add_argument("--state", type=Path, default=Path.home() / ".local/state/freebie-collector")
    parser.add_argument("--repo", type=Path, default=Path.home() / "Documents/assets")
    parser.add_argument("--inbox", type=Path, default=Path.home() / "Downloads/freebie-inbox")
    args = parser.parse_args()
    config = json.loads(args.config.read_text())
    args.state.mkdir(parents=True, exist_ok=True)
    args.inbox.mkdir(parents=True, exist_ok=True)
    db = db_open(args.state / "offers.sqlite3")
    new = 0
    errors: list[str] = []
    ingested: list[Path] = []
    if args.command in ("scan", "run"):
        new, scan_errors = scan(config, db)
        errors.extend(scan_errors)
    if args.command in ("ingest", "run") and args.repo.is_dir():
        downloaded, download_errors = download_declared(config, args.inbox, db)
        new += downloaded
        errors.extend(download_errors)
        prepare_unmanaged_downloads(args.inbox)
        ingested, ingest_errors = ingest(args.inbox, args.repo, db)
        errors.extend(ingest_errors)
    count = export_queue(db, args.state / "claim-queue.md")
    if new or ingested or errors:
        notify(f"new/updated: {new}, ingested: {len(ingested)}, waiting: {count}, errors: {len(errors)}")
    print(json.dumps({"new_or_updated": new, "ingested": [str(p) for p in ingested], "waiting": count, "errors": errors}, ensure_ascii=False))
    return 1 if errors and not count else 0


if __name__ == "__main__":
    raise SystemExit(main())
