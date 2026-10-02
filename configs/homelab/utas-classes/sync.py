#!/usr/bin/env python3
"""Mirror the personal UTAS class calendar (.ics) into a Radicale collection.

UTAS publishes one VEVENT per class meeting (room, [休]/[補] markers included)
at a secret, unauthenticated URL that it rebuilds around 01:00 JST. Radicale
cannot subscribe to a URL, so this copies the events in over CalDAV.

Environment:
    UTAS_ICS_URL       personal calendar URL from UTAS「カレンダー連携」
    RADICALE_URL       collection URL, e.g. http://127.0.0.1:5232/gapul/cal-classes/
    RADICALE_USER, RADICALE_PASSWORD
    STATE_DIRECTORY    set by systemd; holds the hash of each event last written

Only changed events are PUT, so clients do not resync everything daily.
Future events missing from the feed are deleted (cancelled or moved); past
ones are kept, because UTAS may drop a finished semester from the feed.
"""

from __future__ import annotations

import base64
import hashlib
import json
import os
import re
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

JST = timezone(timedelta(hours=9))

# UTAS uses TZID=Asia/Tokyo without defining it. Japan has no DST, so this is exact.
VTIMEZONE = """BEGIN:VTIMEZONE
TZID:Asia/Tokyo
BEGIN:STANDARD
DTSTART:19700101T000000
TZOFFSETFROM:+0900
TZOFFSETTO:+0900
TZNAME:JST
END:STANDARD
END:VTIMEZONE"""

MKCALENDAR_BODY = """<?xml version="1.0" encoding="utf-8"?>
<C:mkcalendar xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav" xmlns:I="http://apple.com/ns/ical/">
  <D:set><D:prop>
    <D:displayname>授業</D:displayname>
    <I:calendar-color>#34C759</I:calendar-color>
    <C:supported-calendar-component-set><C:comp name="VEVENT"/></C:supported-calendar-component-set>
  </D:prop></D:set>
</C:mkcalendar>"""


def request(method: str, url: str, body: str | None = None, headers: dict | None = None) -> tuple[int, str]:
    auth = base64.b64encode(f"{os.environ['RADICALE_USER']}:{os.environ['RADICALE_PASSWORD']}".encode()).decode()
    req = urllib.request.Request(
        url,
        data=body.encode() if body is not None else None,
        method=method,
        headers={"Authorization": f"Basic {auth}", **(headers or {})},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as res:
            return res.status, res.read().decode()
    except urllib.error.HTTPError as err:
        return err.code, err.read().decode(errors="replace")


def parse_events(ics: str) -> dict[str, tuple[str, datetime | None]]:
    """UID -> (VEVENT text, start). Lines are unfolded first."""
    ics = ics.replace("\r\n", "\n").replace("\n ", "")
    events = {}
    for block in re.findall(r"^BEGIN:VEVENT\n.*?^END:VEVENT$", ics, re.S | re.M):
        uid = re.search(r"^UID:(.+)$", block, re.M).group(1).strip()
        start = re.search(r"^DTSTART[^:]*:(\d{8}T\d{6})", block, re.M)
        events[uid] = (block, datetime.strptime(start.group(1), "%Y%m%dT%H%M%S").replace(tzinfo=JST) if start else None)
    return events


def event_hash(block: str) -> str:
    # DTSTAMP/LAST-MODIFIED change on every rebuild; leave them out of the hash.
    stable = "\n".join(line for line in block.splitlines() if not line.startswith(("DTSTAMP", "LAST-MODIFIED")))
    return hashlib.sha256(stable.encode()).hexdigest()


def href_name(uid: str) -> str:
    return re.sub(r"[^A-Za-z0-9_-]", "_", uid) + ".ics"


def main() -> int:
    base = os.environ["RADICALE_URL"].rstrip("/") + "/"
    state_path = Path(os.environ.get("STATE_DIRECTORY", ".")) / "state.json"
    state: dict[str, dict] = json.loads(state_path.read_text()) if state_path.exists() else {}

    with urllib.request.urlopen(os.environ["UTAS_ICS_URL"], timeout=30) as res:
        events = parse_events(res.read().decode())
    print(f"feed: {len(events)} events")

    status, _ = request("PROPFIND", base, headers={"Depth": "0"})
    if status == 404:
        status, body = request("MKCALENDAR", base, MKCALENDAR_BODY, {"Content-Type": "application/xml"})
        if status not in (200, 201):
            print(f"error: MKCALENDAR {status}: {body[:200]}", file=sys.stderr)
            return 1
        print("created collection")
        state = {}

    put = 0
    for uid, (block, start) in events.items():
        digest = event_hash(block)
        if state.get(uid, {}).get("hash") == digest:
            continue
        body = f"BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//gapul//utas-classes//JA\n{VTIMEZONE}\n{block}\nEND:VCALENDAR\n"
        status, text = request("PUT", base + href_name(uid), body.replace("\n", "\r\n"), {"Content-Type": "text/calendar; charset=utf-8"})
        if status not in (200, 201, 204):
            print(f"warning: PUT {uid}: {status}: {text[:200]}", file=sys.stderr)
            continue
        state[uid] = {"hash": digest, "start": start.isoformat() if start else None}
        put += 1

    # An empty feed is more likely a UTAS hiccup than a semester with no classes.
    deleted = 0
    if events:
        now = datetime.now(JST)
        for uid in [u for u in state if u not in events]:
            start = state[uid].get("start")
            if start and datetime.fromisoformat(start) < now:
                continue
            status, _ = request("DELETE", base + href_name(uid))
            if status in (200, 204, 404):
                del state[uid]
                deleted += 1

    state_path.write_text(json.dumps(state))
    print(f"put {put}, deleted {deleted}, tracked {len(state)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
