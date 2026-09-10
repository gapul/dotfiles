#!/usr/bin/env python3
"""Fill one focused macOS text field without exposing its value to the caller.

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
set secretValue to system attribute "ASK_NATIVE_VALUE"

tell application "System Events"
    if UI elements enabled is false then error "accessibility unavailable" number 1703
    set frontProcess to first application process whose frontmost is true
    if bundle identifier of frontProcess is not expectedBundle then ¬
        error "frontmost application mismatch" number 1701
    set focusedElement to value of attribute "AXFocusedUIElement" of frontProcess
    set elementRole to value of attribute "AXRole" of focusedElement
    if elementRole is not "AXTextField" and elementRole is not "AXSecureTextField" and ¬
        elementRole is not "AXTextArea" then error "focused element is not editable" number 1702
    set value of attribute "AXValue" of focusedElement to secretValue
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
        value = payload["value"]
        if not isinstance(bundle_id, str) or not re.fullmatch(
            r"[A-Za-z0-9.-]+", bundle_id
        ):
            raise ValueError("invalid bundle identifier")
        if not isinstance(value, str) or not value:
            raise ValueError("credential value is empty")
    except (KeyError, TypeError, ValueError, json.JSONDecodeError):
        result(False, "invalid request")
        return 2

    env = {**os.environ, "ASK_NATIVE_BUNDLE_ID": bundle_id, "ASK_NATIVE_VALUE": value}
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
    else:
        error = "macOS Accessibility fill failed"
    result(False, error)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
