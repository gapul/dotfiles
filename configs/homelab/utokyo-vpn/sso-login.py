"""Finish UTokyo VPN's SAML login without a person at the keyboard.

openconnect runs this as its --external-browser with the SAML start URL as the
only argument. The page goes through UTokyo Account (Microsoft Entra ID): user
name, password, then a TOTP code from the authenticator-app seed. At the end
Entra hands back to the ASA, whose final page passes the token to openconnect's
listener on localhost:29786 — so getting to that page is the whole job.

Credentials come from $CREDENTIALS_DIRECTORY (systemd LoadCredential):
username, password, totp-secret (the base32 seed, not the otpauth:// URI).
"""

import base64
import hashlib
import hmac
import os
import struct
import sys
import time
from pathlib import Path

from playwright.sync_api import TimeoutError as PlaywrightTimeout
from playwright.sync_api import sync_playwright

CREDS = Path(os.environ["CREDENTIALS_DIRECTORY"])
FAILURE_SHOT = Path(os.environ.get("STATE_DIRECTORY", "/tmp")) / "last-failure.png"


def secret(name: str) -> str:
    return (CREDS / name).read_text().strip()


def totp(seed: str, at: float | None = None) -> str:
    key = base64.b32decode(seed.upper().replace(" ", "") + "=" * (-len(seed) % 8))
    counter = int((time.time() if at is None else at) // 30)
    digest = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    code = struct.unpack(">I", digest[offset : offset + 4])[0] & 0x7FFFFFFF
    return f"{code % 1_000_000:06d}"


def fresh_totp(seed: str) -> str:
    # Entra rejects a code it has already seen, and one about to roll over can
    # expire in flight. Wait out the last few seconds of a window.
    if 30 - time.time() % 30 < 5:
        time.sleep(30 - time.time() % 30 + 1)
    return totp(seed)


def login(url: str) -> None:
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(locale="ja-JP")
        try:
            page.goto(url, wait_until="domcontentloaded")

            page.fill('input[name="loginfmt"]', secret("username"))
            page.click("#idSIButton9")

            page.fill('input[name="passwd"]', secret("password"))
            page.click("#idSIButton9")

            otc = page.locator('input[name="otc"]')
            try:
                otc.wait_for(state="visible", timeout=15_000)
            except PlaywrightTimeout:
                # Entra offered another method (push) first; switch to the code.
                page.click("#signInAnotherWay")
                page.click('[data-value="PhoneAppOTP"]')
                otc.wait_for(state="visible", timeout=15_000)
            otc.fill(fresh_totp(secret("totp-secret")))
            page.click("#idSubmit_SAOTCC_Continue")

            # "Stay signed in?" — either answer works; it does not always appear.
            try:
                page.locator("#idBtn_Back").click(timeout=8_000)
            except PlaywrightTimeout:
                pass

            # The token goes to openconnect from this page's script, not by a
            # navigation, so wait for the page and then for its request.
            page.wait_for_url("**/saml_ac_login.html?done=1", timeout=60_000)
            page.wait_for_load_state("networkidle", timeout=15_000)
        except Exception:
            page.screenshot(path=str(FAILURE_SHOT))
            raise
        finally:
            browser.close()


if __name__ == "__main__":
    # RFC 6238 test vector: seed "12345678901234567890", T=59 -> 287082.
    assert totp(base64.b32encode(b"12345678901234567890").decode(), at=59) == "287082"
    login(sys.argv[1])
