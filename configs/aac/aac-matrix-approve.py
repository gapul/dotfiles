"""Approve one `aac listen` credential request from Matrix.

Run by the patched `aac listen` (AAC_APPROVAL_COMMAND) with AAC_DOMAIN, AAC_DEVICE and
AAC_USERNAME set. Posts the question into the ask broker's approval room with ✅ / ❌ reactions as
buttons and exits 0 only when the approver taps ✅. Everything else — ❌, a timeout, a Matrix
error — exits 1, which aac reads as a denial.

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
    return call(token, "GET", f"/sync?{urllib.parse.urlencode(query)}", timeout=timeout_ms // 1000 + 30)


def answer_in(batch: dict, posted: str) -> bool | None:
    events = batch.get("rooms", {}).get("join", {}).get(ROOM, {}).get("timeline", {}).get("events", [])
    for event in events:
        if event.get("type") != "m.reaction" or event.get("sender") != APPROVER:
            continue
        relates = event.get("content", {}).get("m.relates_to", {})
        if relates.get("event_id") != posted:
            continue
        key = relates.get("key", "").replace("️", "")
        if key == YES:
            return True
        if key == NO:
            return False
    return None


def main() -> int:
    domain = os.environ.get("AAC_DOMAIN", "?")
    device = os.environ.get("AAC_DEVICE", "?")
    username = os.environ.get("AAC_USERNAME", "")
    token = TOKEN_FILE.read_text().strip()

    if call(token, "GET", "/account/whoami").get("user_id") == APPROVER:
        log("refused: bot token is the approver's account")
        return 1

    # Take the sync position before posting, so a fast tap cannot land before it.
    since = sync(token, None, 0)["next_batch"]
    who = f" ({username})" if username else ""
    text = f"[aac] Send the credential for {domain}{who} to {device}?\ntap {YES} / {NO}"
    posted = send(token, "m.room.message", {"msgtype": "m.text", "body": text})
    for key in (YES, NO):
        send(token, "m.reaction", {"m.relates_to": {"rel_type": "m.annotation", "event_id": posted, "key": key}})
    log(f"asked {posted} domain={domain} device={device}")

    deadline = time.monotonic() + TIMEOUT_SECONDS
    verdict = None
    while verdict is None and (left := deadline - time.monotonic()) > 0:
        batch = sync(token, since, int(min(left, 20) * 1000))
        since = batch["next_batch"]
        verdict = answer_in(batch, posted)

    outcome = {True: "approved", False: "denied", None: "timed out"}[verdict]
    log(f"{outcome} {posted}")
    try:
        send(token, "m.room.message", {
            "msgtype": "m.notice",
            "body": f"[aac] {domain}: {outcome}",
            "m.relates_to": {"m.in_reply_to": {"event_id": posted}},
        })
    except Exception as exc:  # the answer still stands
        log(f"notice failed: {exc}")
    return 0 if verdict else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        log(f"error: {exc!r}")
        sys.exit(1)
