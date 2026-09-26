#!/usr/bin/env python3
"""Merge several remote iCalendar sources into token-addressed .ics feeds.

This replaces a container image that used to be built from a private repo. The
whole job is: fetch a handful of .ics URLs, keep the events inside a time
window, optionally prefix their summaries, and write one file per feed. A file
per feed is enough because the feed URL is the secret: Caddy serves the output
directory verbatim, so `<token>.ics` is the unguessable path.

Config (YAML) and tokens come from the environment so that nothing secret is in
the Nix store:

    CONFIG_FILE  path to the YAML described in secrets/homelab.yaml
    OUT_DIR      directory to write `<token>.ics` into
    <tokenEnv>   one per feed, named by the feed's `tokenEnv` field

A source that fails to fetch is skipped with a warning rather than failing the
run: one dead calendar should not take the whole feed offline, and the previous
output stays in place until the next successful run replaces it.
"""

from __future__ import annotations

import os
import sys
import urllib.error
import urllib.request
from datetime import date, datetime, timedelta, timezone

import yaml
from icalendar import Calendar

USER_AGENT = "unified-calendar/1.0 (+https://gapul.net)"
TIMEOUT = 30


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        return response.read()


def as_datetime(value) -> datetime | None:
    """Normalise DTSTART to an aware datetime so events can be compared.

    All-day events carry a `date`, timed ones a `datetime` that may or may not
    have a timezone. Anything else (a malformed source) is treated as unknown
    and kept, because dropping events on a parsing detail is worse than keeping
    a few stale ones.
    """
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    if isinstance(value, date):
        return datetime(value.year, value.month, value.day, tzinfo=timezone.utc)
    return None


def in_window(event, start: datetime, end: datetime) -> bool:
    dtstart = event.get("DTSTART")
    if dtstart is None:
        return True
    moment = as_datetime(dtstart.dt)
    if moment is None:
        return True
    # A recurring event is only anchored by its first occurrence, so keeping it
    # whenever the rule is open-ended is the only correct call here.
    if event.get("RRULE") is not None:
        return moment <= end
    return start <= moment <= end


def load_events(config: dict, window_start: datetime, window_end: datetime) -> list:
    prefix_summaries = bool(config.get("output", {}).get("prefixSummaries"))
    events = []
    for source in config.get("calendars", []):
        if not source.get("enabled", True):
            continue
        name = source.get("name") or source.get("id") or "?"
        try:
            raw = fetch(source["url"])
        except (urllib.error.URLError, OSError, KeyError) as err:
            print(f"warning: {name}: fetch failed: {err}", file=sys.stderr)
            continue
        try:
            calendar = Calendar.from_ical(raw)
        except ValueError as err:
            print(f"warning: {name}: parse failed: {err}", file=sys.stderr)
            continue

        # `prefix` may be an explicit empty string, which means "no prefix even
        # though prefixSummaries is on" — so only fall back when the key is absent.
        prefix = source.get("prefix", name) if prefix_summaries else ""
        kept = 0
        for event in calendar.walk("VEVENT"):
            if not in_window(event, window_start, window_end):
                continue
            if prefix:
                summary = str(event.get("SUMMARY", ""))
                event["SUMMARY"] = f"[{prefix}] {summary}" if summary else f"[{prefix}]"
            events.append(event)
            kept += 1
        print(f"{name}: {kept} events", file=sys.stderr)
    return events


def build_feed(events: list, feed: dict, timezone_name: str) -> bytes:
    calendar = Calendar()
    calendar.add("prodid", "-//gapul//unified-calendar//JA")
    calendar.add("version", "2.0")
    calendar.add("x-wr-calname", feed.get("calName", "Calendar"))
    calendar.add("x-wr-timezone", timezone_name)

    busy = feed.get("mode") == "busy"
    busy_title = feed.get("busyTitle", "Busy")
    for event in events:
        if busy:
            # Strip everything that could leak what the appointment is. The
            # point of this feed is "that slot is taken", nothing more.
            copy = type(event)()
            for key in ("DTSTART", "DTEND", "DURATION", "UID", "RRULE", "EXDATE", "RECURRENCE-ID"):
                if event.get(key) is not None:
                    # Assign rather than add(): these properties are already parsed,
                    # and add() re-encodes them — which throws on list-valued ones
                    # such as EXDATE.
                    copy[key] = event[key]
            copy.add("summary", busy_title)
            copy.add("transp", "OPAQUE")
            calendar.add_component(copy)
        else:
            calendar.add_component(event)
    return calendar.to_ical()


def main() -> int:
    config_file = os.environ["CONFIG_FILE"]
    out_dir = os.environ["OUT_DIR"]
    with open(config_file, encoding="utf-8") as handle:
        config = yaml.safe_load(handle)

    window = config.get("output", {}).get("window", {})
    now = datetime.now(timezone.utc)
    window_start = now - timedelta(days=int(window.get("pastDays", 60)))
    window_end = now + timedelta(days=int(window.get("futureDays", 400)))
    timezone_name = config.get("output", {}).get("timezone", "UTC")

    events = load_events(config, window_start, window_end)
    if not events:
        # Publishing an empty calendar would silently wipe every subscriber's
        # view, which is worse than leaving yesterday's copy in place.
        print("error: no events collected; keeping previous output", file=sys.stderr)
        return 1

    os.makedirs(out_dir, exist_ok=True)
    written = set()
    for feed in config.get("feeds", []):
        token = os.environ.get(feed["tokenEnv"], "").strip()
        if not token:
            print(f"warning: {feed['id']}: {feed['tokenEnv']} is empty, skipping", file=sys.stderr)
            continue
        body = build_feed(events, feed, timezone_name)
        target = os.path.join(out_dir, f"{token}.ics")
        temporary = target + ".new"
        with open(temporary, "wb") as handle:
            handle.write(body)
        os.replace(temporary, target)
        os.chmod(target, 0o644)
        written.add(os.path.basename(target))
        print(f"{feed['id']}: wrote {len(body)} bytes", file=sys.stderr)

    # A rotated token must stop working, so anything not written this run goes.
    for name in os.listdir(out_dir):
        if name.endswith(".ics") and name not in written:
            os.remove(os.path.join(out_dir, name))
    return 0


if __name__ == "__main__":
    sys.exit(main())
