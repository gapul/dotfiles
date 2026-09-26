#!/usr/bin/env python3
"""Watch IMAP inboxes for verification codes and put them on the clipboard.

macOS only autofills codes from Mail.app into Safari, and the browser in daily
use here is Zen. This is the browser-agnostic version: every new mail is
scanned for a 4-8 digit code near a "code"-like word, the code goes to pbcopy
and a notification says so. Paste with cmd+V.

Accounts come from aerc's accounts.conf (source = imaps://USER@HOST:PORT and
source-cred-cmd), so there is no second copy of any credential. Only mailboxes
that receive mail directly are useful: the Stalwart mirrors lag an hour.

    watch.py            # run forever (launchd does this)
    watch.py --selftest # the extraction heuristic against known mails
"""

import configparser
import email
import email.policy
import imaplib
import re
import subprocess
import sys
import threading
import time
from pathlib import Path

ACCOUNTS = Path.home() / ".config/aerc/accounts.conf"
POLL_SECONDS = 5

KEYWORD = re.compile(
    r"(code|passcode|pin|otp|one[- ]?time|verif|confirm|認証|確認|コード|ワンタイム|暗証)",
    re.I,
)
# 4-8 digits not glued to other digits or a dash (phone numbers, order ids).
CANDIDATE = re.compile(r"(?<![\d-])(\d{4,8})(?![\d-])")


def extract_code(subject: str, body: str) -> str | None:
    """Return the most likely verification code, or None.

    ponytail: digits only. Alphanumeric codes (ABCD-1234) are not handled;
    add a second pattern when one actually shows up.
    """
    text = f"{subject}\n{body}"

    def plausible(m: re.Match) -> bool:
        s = m.group(1)
        return not (len(s) == 4 and 1900 <= int(s) <= 2099)  # a year, not a code

    # Nearest candidate within 120 chars after a keyword.
    for kw in KEYWORD.finditer(text):
        window = text[kw.end() : kw.end() + 120]
        for m in CANDIDATE.finditer(window):
            if plausible(m):
                return m.group(1)
    # Keyword in the subject and exactly one candidate in the whole mail.
    if KEYWORD.search(subject):
        cands = [m.group(1) for m in CANDIDATE.finditer(text) if plausible(m)]
        if len(set(cands)) == 1:
            return cands[0]
    return None


def mail_text(msg: email.message.EmailMessage) -> str:
    part = msg.get_body(preferencelist=("plain", "html"))
    if part is None:
        return ""
    text = part.get_content()
    if part.get_content_type() == "text/html":
        text = re.sub(r"<[^>]+>", " ", text)
    return text


def notify(code: str, sender: str) -> None:
    subprocess.run(["/usr/bin/pbcopy"], input=code.encode(), check=False)
    q = lambda s: s.replace("\\", "\\\\").replace('"', '\\"')
    subprocess.run(
        [
            "/usr/bin/osascript",
            "-e",
            f'display notification "Copied {q(code)} to the clipboard" with title "Mail code" subtitle "{q(sender[:60])}"',
        ],
        check=False,
    )


def accounts() -> list[tuple[str, str, str, int, str]]:
    cp = configparser.ConfigParser(interpolation=None)
    cp.read(ACCOUNTS)
    out = []
    for name in cp.sections():
        src = cp[name].get("source", "")
        m = re.match(r"imaps://([^@]+@[^@]+)@([^:]+):(\d+)", src)
        if not m or "source-cred-cmd" not in cp[name]:
            continue
        pw = subprocess.run(
            cp[name]["source-cred-cmd"], shell=True, capture_output=True, text=True, check=True
        ).stdout.strip()
        out.append((name, m.group(1), m.group(2), int(m.group(3)), pw))
    return out


def watch(name: str, user: str, host: str, port: int, password: str) -> None:
    last_uid = None
    while True:
        try:
            conn = imaplib.IMAP4_SSL(host, port)
            conn.login(user, password)
            conn.select("INBOX", readonly=True)
            if last_uid is None:
                _, data = conn.uid("search", None, "ALL")
                uids = data[0].split()
                last_uid = int(uids[-1]) if uids else 0
            print(f"{name}: watching from uid {last_uid}", flush=True)
            while True:
                conn.noop()
                _, data = conn.uid("search", None, f"UID {last_uid + 1}:*")
                for uid in (int(u) for u in data[0].split()):
                    if uid <= last_uid:  # N:* also returns the newest existing message
                        continue
                    last_uid = uid
                    _, raw = conn.uid("fetch", str(uid), "(BODY.PEEK[])")
                    msg = email.message_from_bytes(raw[0][1], policy=email.policy.default)
                    code = extract_code(str(msg.get("Subject", "")), mail_text(msg))
                    sender = str(msg.get("From", ""))
                    if code:
                        notify(code, sender)
                        print(f"{name}: {code} from {sender}", flush=True)
                time.sleep(POLL_SECONDS)
        except Exception as e:  # noqa: BLE001 — any IMAP/network failure: reconnect
            print(f"{name}: {e!r}, reconnecting", file=sys.stderr, flush=True)
            time.sleep(15)


def selftest() -> None:
    assert extract_code("Your verification code", "Use 482913 to sign in. Sent 2026-09-26.") == "482913"
    assert extract_code("【認証コード】ログイン", "認証コードは 1234 です。有効期限は2026年です。") == "1234"
    assert extract_code("Order shipped", "Order 48291 will arrive on 2026-10-01.") is None
    assert extract_code("Confirm your address", "Call 03-1234-5678. Your PIN: 0071.") == "0071"
    assert extract_code("Receipt", "Total 12000 yen. Reference 88771234.") is None
    print("selftest ok")


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        selftest()
        sys.exit(0)
    accts = accounts()
    if not accts:
        sys.exit(f"no imaps accounts with source-cred-cmd in {ACCOUNTS}")
    for a in accts:
        threading.Thread(target=watch, args=a, daemon=True).start()
    while True:
        time.sleep(3600)
