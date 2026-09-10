#!/usr/bin/env python3
"""Fill one focused macOS login field without exposing its value to the caller.

The broker sends a small JSON object on stdin. The value is passed to the system AppleScript
process only through its environment: it never appears in argv, stdout, stderr, or the audit log.
The frontmost bundle and focused Accessibility role are checked immediately before the write.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys


SCRIPT = r"""
set expectedBundle to system attribute "ASK_NATIVE_BUNDLE_ID"
set expectedDomain to system attribute "ASK_NATIVE_DOMAIN"
set inputMode to system attribute "ASK_NATIVE_INPUT_MODE"
set secretValue to system attribute "ASK_NATIVE_VALUE"

tell application "System Events"
    if UI elements enabled is false then error "accessibility unavailable" number 1703
    set frontProcess to first application process whose frontmost is true
    if bundle identifier of frontProcess is not expectedBundle then ¬
        error "frontmost application mismatch" number 1701
    if expectedDomain is not "" then
        if expectedBundle is not "com.apple.Safari" then error "page domain mismatch" number 1704
        -- Read Safari's visible address field through Accessibility. This avoids granting the
        -- helper broad Apple Events control over Safari while keeping the URL check adjacent to
        -- the focused-field write. Safari 26 places the smart search field one group below the
        -- toolbar; refuse if that signed UI structure is not present rather than guessing.
        set pageURL to ""
        set frontToolbar to first UI element of front window of frontProcess whose role is "AXToolbar"
        repeat with toolbarGroup in UI elements of frontToolbar
            repeat with toolbarItem in UI elements of toolbarGroup
                try
                    if role of toolbarItem is "AXTextField" and ¬
                        description of toolbarItem is "smart search field" then
                        set pageURL to value of toolbarItem as text
                    end if
                end try
            end repeat
        end repeat
        set allowedOrigin to "https://" & expectedDomain
        set allowedPrefix to allowedOrigin & "/"
        if pageURL is not allowedOrigin and pageURL does not start with allowedPrefix then ¬
            error "page domain mismatch" number 1704
    end if
    set focusedElement to value of attribute "AXFocusedUIElement" of frontProcess
    set elementRole to value of attribute "AXRole" of focusedElement
    if elementRole is "AXTextField" or elementRole is "AXSecureTextField" or ¬
        elementRole is "AXTextArea" then
        set value of attribute "AXValue" of focusedElement to secretValue
    else if inputMode is "keystroke" and elementRole is "AXGroup" then
        -- Some CEF login windows, notably Creative Cloud 6.x, hide their focused HTML input
        -- behind one AXGroup. The broker enables this mode per bundle; it is never the default.
        keystroke secretValue
    else
        error "focused element is not editable" number 1702
    end if
    return elementRole
end tell
"""


def result(filled: bool, error: str | None = None) -> None:
    payload: dict[str, object] = {"filled": filled}
    if error:
        payload["error"] = error
    print(json.dumps(payload, separators=(",", ":")))


def main() -> int:
    try:
        raw = sys.stdin.buffer.read(1_048_577)
        if len(raw) > 1_048_576:
            raise ValueError("request is too large")
        payload = json.loads(raw)
        bundle_id = payload["bundle_id"]
        expected_domain = payload.get("expected_domain", "")
        input_mode = payload.get("input_mode", "ax_value")
        value = payload["value"]
        if not isinstance(bundle_id, str) or not re.fullmatch(
            r"[A-Za-z0-9.-]+", bundle_id
        ):
            raise ValueError("invalid bundle identifier")
        if input_mode not in {"ax_value", "keystroke"}:
            raise ValueError("invalid input mode")
        if expected_domain and not re.fullmatch(
            r"[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?", expected_domain
        ):
            raise ValueError("invalid expected domain")
        if not isinstance(value, str) or not value:
            raise ValueError("credential value is empty")
    except (KeyError, TypeError, ValueError, json.JSONDecodeError):
        result(False, "invalid request")
        return 2

    env = {
        **os.environ,
        "ASK_NATIVE_BUNDLE_ID": bundle_id,
        "ASK_NATIVE_DOMAIN": expected_domain,
        "ASK_NATIVE_INPUT_MODE": input_mode,
        "ASK_NATIVE_VALUE": value,
    }
    try:
        completed = subprocess.run(
            ["/usr/bin/osascript", "-"],
            input=SCRIPT,
            text=True,
            capture_output=True,
            env=env,
            timeout=15,
            check=False,
        )
    except subprocess.TimeoutExpired:
        result(False, "native application did not respond")
        return 1
    finally:
        env.pop("ASK_NATIVE_VALUE", None)
        value = ""

    if completed.returncode == 0:
        result(True)
        return 0

    stderr = completed.stderr
    if "1701" in stderr:
        error = "configured application is not frontmost"
    elif "1702" in stderr:
        error = "focused element is not an editable text field"
    elif "1703" in stderr:
        error = "Accessibility permission is unavailable"
    elif "1704" in stderr:
        error = "native browser page does not match the approved domain"
    else:
        error = "macOS Accessibility fill failed"
    result(False, error)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
