"""Approve one `aac listen` credential request from Matrix.

Run by the patched `aac listen` (AAC_APPROVAL_COMMAND) with AAC_DOMAIN, AAC_DEVICE and
AAC_USERNAME set. Posts the question into the ask broker's approval room with ✅ / ❌ reactions as
buttons and exits 0 only when the approver taps ✅. Everything else — ❌, a timeout, a Matrix
error — exits 1, which aac reads as a denial.

When several vault items match, aac sets AAC_CANDIDATES instead (a JSON list of name / username /
uri, no secrets). The buttons are then 1️⃣…9️⃣ and ❌, and a Matrix reply to the question with a
number works too (the only way past nine), as does a plain message holding just the number: aac
asks one question at a time and only messages after this one are read, so it cannot answer another. The chosen number goes to stdout with exit 0, which aac
reads as "send that one".

The bot token is readable by the agents, so the answer only counts when it comes from the
approver's own account, as a reaction to this exact message. The bot's own reactions (the buttons)
are ignored, and the bot must not be the approver.
"""

import json
import os
import sys
import time
import urllib.parse
import urllib.request
import uuid
from datetime import datetime
from pathlib import Path

HOMESERVER = "https://matrix.gapul.net"
ROOM = "!SgoLc7XqTg7UqSDc0k_zjHYIZ3obMblRF68WZQKrZrU"
TOKEN_FILE = Path.home() / ".config/ask/matrix-token"
APPROVER = "@gapul:gapul.net"
# `aac run` gives up after 120 s by default; answer (as a denial) before it does.
TIMEOUT_SECONDS = 110
LOG = Path.home() / ".local/state/aac/approve.log"

YES, NO = "✅", "❌"
# Past this a list is no use on a phone; narrow the search or ask by --id.
MAX_CANDIDATES = 30
# Keycap emoji for candidates. Clients differ on the U+FE0F variation selector, so keys are
# compared with it stripped.
KEYCAPS = [f"{n}️⃣" for n in range(1, 10)]


def bare(key: str) -> str:
    return key.replace("️", "")


def log(message: str) -> None:
    LOG.parent.mkdir(parents=True, exist_ok=True)
    with LOG.open("a") as f:
        f.write(f"{datetime.now().isoformat(timespec='seconds')} {message}\n")


def call(token: str, method: str, path: str, body: dict | None = None, timeout: int = 30) -> dict:
    request = urllib.request.Request(
        f"{HOMESERVER}/_matrix/client/v3{path}",
        data=None if body is None else json.dumps(body).encode(),
        method=method,
        # Python-urllib's default User-Agent gets a 403 from the proxy in front of matrix.gapul.net.
        headers={
            "Authorization": f"Bearer {token}",
            "User-Agent": "aac-matrix-approve",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read())


def send(token: str, event_type: str, content: dict) -> str:
    room = urllib.parse.quote(ROOM)
    path = f"/rooms/{room}/send/{event_type}/{uuid.uuid4().hex}"
    return call(token, "PUT", path, content)["event_id"]


def sync(token: str, since: str | None, timeout_ms: int) -> dict:
    room_filter = json.dumps({"room": {"rooms": [ROOM], "timeline": {"limit": 50}}})
    query = {"timeout": str(timeout_ms), "filter": room_filter}
    if since:
        query["since"] = since
    return call(
        token, "GET", f"/sync?{urllib.parse.urlencode(query)}", timeout=timeout_ms // 1000 + 30
    )


def answer_in(batch: dict, posted: str, buttons: dict[str, str], choices: int = 0) -> str | None:
    """The approver's answer to `posted`: a reaction mapped through `buttons` (bare key → answer),
    or, when there are `choices`, a number from 1 to `choices` in a reply to it or a plain message
    (one that replies to some other message does not count)."""
    events = (
        batch.get("rooms", {}).get("join", {}).get(ROOM, {}).get("timeline", {}).get("events", [])
    )
    for event in events:
        if event.get("sender") != APPROVER:
            continue
        content = event.get("content", {})
        relates = content.get("m.relates_to", {}) or {}
        if event.get("type") == "m.reaction":
            if relates.get("event_id") != posted:
                continue
            answer = buttons.get(bare(relates.get("key", "")))
            if answer is not None:
                return answer
        elif event.get("type") == "m.room.message" and choices:
            replied = (relates.get("m.in_reply_to") or {}).get("event_id")
            if replied not in (None, posted):
                continue
            # A reply body quotes the original as "> " lines first.
            text = "\n".join(
                line for line in content.get("body", "").splitlines() if not line.startswith(">")
            ).strip()
            if text.isdigit() and 1 <= int(text) <= choices:
                return text
    return None


def host(uri: str | None) -> str:
    return urllib.parse.urlsplit(uri or "").hostname or (uri or "?")


def question(
    domain: str, device: str, username: str, candidates: list[dict] | None
) -> tuple[str, dict[str, str]]:
    """Message text and buttons (key → answer, in display order)."""
    if candidates is None:
        who = f" ({username})" if username else ""
        text = f"[aac] Send the credential for {domain}{who} to {device}?\ntap {YES} / {NO}"
        return text, {YES: "yes", NO: "no"}
    lines = [
        f"  {i}. {c.get('name') or '?'} — {c.get('username') or 'no username'} ({host(c.get('uri'))})"
        for i, c in enumerate(candidates, 1)
    ]
    text = "\n".join(
        [
            f"[aac] {len(candidates)} credentials match {domain}. Which one goes to {device}?",
            *lines,
            f"tap a number, or {NO} to deny",
        ]
    )
    if len(candidates) > len(KEYCAPS):
        text = text.replace("tap a number", f"tap 1–{len(KEYCAPS)} or send the number")
    buttons = {KEYCAPS[i]: str(i + 1) for i in range(min(len(candidates), len(KEYCAPS)))}
    buttons[NO] = "no"
    return text, buttons


def main() -> int:
    domain = os.environ.get("AAC_DOMAIN", "?")
    device = os.environ.get("AAC_DEVICE", "?")
    username = os.environ.get("AAC_USERNAME", "")
    raw = os.environ.get("AAC_CANDIDATES")
    candidates = json.loads(raw) if raw else None
    if candidates is not None and not 1 <= len(candidates) <= MAX_CANDIDATES:
        log(f"denied: {len(candidates)} candidates for {domain}, more than {MAX_CANDIDATES}")
        return 1
    token = TOKEN_FILE.read_text().strip()

    if call(token, "GET", "/account/whoami").get("user_id") == APPROVER:
        log("refused: bot token is the approver's account")
        return 1

    # Take the sync position before posting, so a fast tap cannot land before it.
    since = sync(token, None, 0)["next_batch"]
    text, buttons = question(domain, device, username, candidates)
    posted = send(token, "m.room.message", {"msgtype": "m.text", "body": text})
    for key in buttons:
        send(
            token,
            "m.reaction",
            {"m.relates_to": {"rel_type": "m.annotation", "event_id": posted, "key": key}},
        )
    log(f"asked {posted} domain={domain} device={device} candidates={len(candidates or [])}")

    by_key = {bare(k): v for k, v in buttons.items()}
    deadline = time.monotonic() + TIMEOUT_SECONDS
    answer = None
    while answer is None and (left := deadline - time.monotonic()) > 0:
        batch = sync(token, since, int(min(left, 20) * 1000))
        since = batch["next_batch"]
        answer = answer_in(batch, posted, by_key, len(candidates or []))

    if answer is None:
        outcome = "timed out"
    elif answer == "no":
        outcome = "denied"
    elif candidates is None:
        outcome = "approved"
    else:
        outcome = f"approved #{answer} ({candidates[int(answer) - 1].get('name')})"
    log(f"{outcome} {posted}")
    try:
        send(
            token,
            "m.room.message",
            {
                "msgtype": "m.notice",
                "body": f"[aac] {domain}: {outcome}",
                "m.relates_to": {"m.in_reply_to": {"event_id": posted}},
            },
        )
    except Exception as exc:  # the answer still stands
        log(f"notice failed: {exc}")

    if answer is None or answer == "no":
        return 1
    if candidates is not None:
        print(answer)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        log(f"error: {exc!r}")
        sys.exit(1)
