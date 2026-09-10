#!/usr/bin/env python3
"""ask broker — the thing that holds the vault session and asks the human.

Protocol: docs/ask-protocol.md in the dotfiles repo. Read that first; this file implements it and
does not restate the reasoning.

Runs on the workstation as a launchd agent in the GUI session, and listens on the tailnet so that
an agent working on the mac mini reaches the same broker.

The single rule this file is arranged around: **no code path returns a credential to the caller.**
The login tools type values into a browser or approved native app and answer whether that worked.
There is deliberately no `get_password`, not even a private one.
"""

from __future__ import annotations

import asyncio
import json
import os
import shutil
import subprocess
import tempfile
import time
import tomllib
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Literal

from mcp.server.fastmcp import Context, FastMCP
from pydantic import BaseModel, Field

CONFIG_PATH = Path(os.environ.get("ASK_CONFIG", Path.home() / ".config/ask/broker.toml"))


# --------------------------------------------------------------------------------------- config


@dataclass(frozen=True)
class Config:
    host: str = "127.0.0.1"
    port: int = 8933

    # Only these domains can ever be the subject of login_fill. An approval for anything else is
    # refused before the vault is touched, which is what bounds a mistaken or forged approval.
    allowed_domains: tuple[str, ...] = ()

    # Named execution targets. Each target may be local or an SSH host, and each application is
    # independently constrained to domains whose credentials it may receive.
    native_targets: dict[str, dict[str, Any]] = field(default_factory=dict)

    # Re-lock the vault after this long without a release. A leaked session key expires.
    vault_idle_seconds: int = 900

    # How long the person at the terminal gets before the question goes to their phone.
    #
    # 25s was the first guess and it was wrong: the dialog appears, and a person who has to
    # notice it, read what is being asked and decide has usually not finished in that time. The
    # cost of being generous here is only that someone who has actually walked away waits longer
    # for their phone to buzz, which matters far less than timing out on someone who is present.
    local_timeout_seconds: int = 90
    remote_timeout_seconds: int = 600

    # The .app that raises the Touch ID prompt. Empty or missing means that channel is skipped and
    # the dialog answers instead.
    touch_id_app: str = "~/Applications/AskApprove.app"

    # Read at unlock time and dropped immediately. A sops-managed file, mode 0400, which is how
    # every other secret on this machine is handled. The lock is the second layer here; the
    # approval is the first, so an auto-unlock does not remove the gate.
    vault_password_file: str = ""

    matrix_homeserver: str = ""
    matrix_room: str = ""
    matrix_token_file: str = ""

    # Required when the broker is reachable from anywhere but this machine. Binding to the tailnet
    # so an agent on the mac mini can ask means anything else on the tailnet can ask too — the
    # approval still guards release, but nothing would stop a flood of requests without this.
    # A file rather than a literal so it can be sops-managed like everything else here.
    token_file: str = ""

    audit_log: Path = Path.home() / ".local/state/ask/audit.jsonl"

    @classmethod
    def load(cls, path: Path = CONFIG_PATH) -> "Config":
        if not path.exists():
            return cls()
        raw = tomllib.loads(path.read_text())
        broker = raw.get("broker", {})
        matrix = raw.get("matrix", {})
        return cls(
            host=broker.get("host", cls.host),
            port=broker.get("port", cls.port),
            allowed_domains=tuple(broker.get("allowed_domains", ())),
            native_targets=raw.get("native_targets", {}),
            vault_idle_seconds=broker.get("vault_idle_seconds", cls.vault_idle_seconds),
            local_timeout_seconds=broker.get("local_timeout_seconds", cls.local_timeout_seconds),
            remote_timeout_seconds=broker.get("remote_timeout_seconds", cls.remote_timeout_seconds),
            vault_password_file=broker.get("vault_password_file", ""),
            token_file=broker.get("token_file", ""),
            touch_id_app=broker.get("touch_id_app", cls.touch_id_app),
            matrix_homeserver=matrix.get("homeserver", ""),
            matrix_room=matrix.get("room", ""),
            matrix_token_file=matrix.get("token_file", ""),
            audit_log=Path(broker.get("audit_log", str(cls.audit_log))).expanduser(),
        )


CONFIG = Config.load()


def replace_allowlist(domains: tuple[str, ...]) -> Config:
    """Only for tests: Config is frozen, so swap the whole thing."""
    from dataclasses import replace

    return replace(CONFIG, allowed_domains=domains)


# ---------------------------------------------------------------------------------------- audit


def audit(event: str, **fields: Any) -> None:
    """Append-only record of what was asked and what came back. Never holds a secret: the whole
    point is that this file can be read freely afterwards."""
    CONFIG.audit_log.parent.mkdir(parents=True, exist_ok=True)
    line = {"at": datetime.now(timezone.utc).isoformat(), "event": event, **fields}
    with CONFIG.audit_log.open("a") as f:
        f.write(json.dumps(line, ensure_ascii=False) + "\n")


# ---------------------------------------------------------------------------------------- vault


class Vault:
    """Wraps `bw`. Holds the session key in this process and nowhere else."""

    def __init__(self) -> None:
        self._session: str | None = None
        self._last_used = 0.0

    def _bw(self) -> str:
        path = shutil.which("bw")
        if not path:
            raise RuntimeError("bw is not on PATH")
        return path

    def ensure_unlocked(self) -> None:
        """Unlock from the password file if the session has expired or was never opened."""
        self._expire_if_idle()
        if self._session:
            return
        if not CONFIG.vault_password_file:
            raise RuntimeError("vault is locked and no vault_password_file is configured")
        password = Path(CONFIG.vault_password_file).expanduser().read_text().strip()
        try:
            self.unlock(password)
        finally:
            del password
        audit("vault.unlocked")

    def unlock(self, password: str) -> None:
        out = subprocess.run(
            [self._bw(), "unlock", "--raw", "--passwordenv", "ASK_BW_PASSWORD"],
            env={**os.environ, "ASK_BW_PASSWORD": password},
            capture_output=True,
            text=True,
        )
        if out.returncode != 0:
            raise RuntimeError("bw unlock failed")
        self._session = out.stdout.strip()
        self._last_used = time.time()

    def _expire_if_idle(self) -> None:
        if self._session and time.time() - self._last_used > CONFIG.vault_idle_seconds:
            self._session = None
            audit("vault.relocked")

    @property
    def unlocked(self) -> bool:
        self._expire_if_idle()
        return self._session is not None

    def candidates(self, domain: str) -> list[tuple[str, str]]:
        """(id, name) for every vault item matching the domain.

        More than one is normal — a personal and a work account on the same site — and the
        broker must not guess between them. The names come back so the human can pick; they are
        not credentials, but they do describe the vault, so nothing outside this process sees
        them except the person answering and the audit log.
        """
        self.ensure_unlocked()
        out = subprocess.run(
            [self._bw(), "list", "items", "--search", domain],
            env={**os.environ, "BW_SESSION": self._session},
            capture_output=True,
            text=True,
        )
        if out.returncode != 0:
            raise RuntimeError("bw list items failed")
        self._last_used = time.time()
        try:
            items = json.loads(out.stdout)
        except json.JSONDecodeError:
            raise RuntimeError("bw list items returned nothing parseable") from None
        # --search is fuzzy: it matches names and notes too, so a plain search for google.com
        # came back with ten items here. Keep only those whose login URIs actually name the
        # domain, so the human is choosing between real candidates rather than a haystack.
        out_items = []
        for item in items:
            login = item.get("login") or {}
            uris = [u.get("uri") or "" for u in (login.get("uris") or [])]
            if any(host_matches(u, domain) for u in uris):
                out_items.append((item["id"], item.get("name") or item["id"]))
        return out_items

    def get(self, what: str, key: str) -> str:
        """`what` is bw's object name: password, username, totp, uri."""
        self.ensure_unlocked()
        out = subprocess.run(
            [self._bw(), "get", what, key],
            env={**os.environ, "BW_SESSION": self._session},
            capture_output=True,
            text=True,
        )
        if out.returncode != 0:
            raise RuntimeError(f"bw get {what} failed")
        self._last_used = time.time()
        return out.stdout.strip()


VAULT = Vault()


# --------------------------------------------------------------------------------------- asking


@dataclass
class Request:
    kind: Literal["approve", "choose", "ask_text", "login_fill", "native_login_fill"]
    prompt: str
    requester: str
    options: list[str] = field(default_factory=list)
    domain: str | None = None
    fields: list[str] = field(default_factory=list)
    id: str = field(default_factory=lambda: uuid.uuid4().hex[:12])

    def as_json(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "kind": self.kind,
            "createdAt": datetime.now(timezone.utc).isoformat(),
            "prompt": self.prompt,
            "options": self.options,
            "domain": self.domain,
            "fields": self.fields,
            "requester": self.requester,
        }


class Matrix:
    """Posts the question into a room and waits for a reply. Element on the phone is the client.

    Deliberately the dumbest thing that works: send, then poll for a message from someone other
    than us. Replacing this with APNs straight to the watch app changes only this class.
    """

    def __init__(self, cfg: Config) -> None:
        self.cfg = cfg

    @property
    def configured(self) -> bool:
        return bool(self.cfg.matrix_homeserver and self.cfg.matrix_room and self.cfg.matrix_token_file)

    def _token(self) -> str:
        return Path(self.cfg.matrix_token_file).expanduser().read_text().strip()

    async def ask(self, request: Request, timeout: int) -> str | None:
        import urllib.error
        import urllib.request

        token = self._token()
        base = self.cfg.matrix_homeserver.rstrip("/")
        room = self.cfg.matrix_room

        body = f"[ask] {request.prompt}\nfrom: {request.requester}"
        if request.options:
            body += "\noptions: " + " / ".join(request.options)
        if request.kind in ("approve", "login_fill", "native_login_fill"):
            body += "\nreply: yes / no"

        def post() -> None:
            req = urllib.request.Request(
                f"{base}/_matrix/client/v3/rooms/{room}/send/m.room.message/{uuid.uuid4().hex}",
                method="PUT",
                data=json.dumps({"msgtype": "m.text", "body": body}).encode(),
                headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
            )
            urllib.request.urlopen(req, timeout=20).read()

        def sync(since: str | None) -> tuple[str, list[str]]:
            url = f"{base}/_matrix/client/v3/sync?timeout=20000"
            if since:
                url += f"&since={since}"
            req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
            data = json.loads(urllib.request.urlopen(req, timeout=40).read())
            texts: list[str] = []
            joined = data.get("rooms", {}).get("join", {}).get(room, {})
            for event in joined.get("timeline", {}).get("events", []):
                if event.get("type") != "m.room.message":
                    continue
                content = event.get("content", {})
                if content.get("msgtype") == "m.text":
                    texts.append(content.get("body", ""))
            return data.get("next_batch", ""), texts

        loop = asyncio.get_running_loop()
        since, _ = await loop.run_in_executor(None, sync, None)  # start from now
        await loop.run_in_executor(None, post)

        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                since, texts = await loop.run_in_executor(None, sync, since)
            except Exception:
                await asyncio.sleep(2)
                continue
            for text in texts:
                answer = text.strip()
                if answer and not answer.startswith("[ask]"):
                    return answer
        return None


MATRIX = Matrix(CONFIG)


class YesNo(BaseModel):
    """Elicitation wants a schema, and only primitive fields are allowed."""

    approved: bool = Field(description="Approve this request?")


class Choice(BaseModel):
    choice: str = Field(description="One of the offered options")


class FreeText(BaseModel):
    text: str = Field(description="Your answer")


def _schema_for(kind: str) -> type[BaseModel]:
    if kind in ("approve", "login_fill", "native_login_fill"):
        return YesNo
    if kind == "choose":
        return Choice
    return FreeText


async def touch_id(request: Request, prompt: str) -> str | None:
    """Touch ID, or a paired Apple Watch — the policy is BiometricsOrCompanion.

    Launched with `open`, not by running the binary. That distinction is the whole reason this
    works: executed directly, even signed and inside a bundle, `LAContext.evaluatePolicy` returns
    systemCancel without drawing anything, because the process is not a GUI application as far as
    the window server is concerned. Going through LaunchServices makes it one. Six variations were
    tried before that turned out to be the difference.

    `open -W` waits but does not carry the exit code back, so the verdict comes through a file.
    """
    app = Path(CONFIG.touch_id_app).expanduser()
    if not CONFIG.touch_id_app or not app.exists():
        return None
    if request.kind not in ("approve", "login_fill", "native_login_fill"):
        return None  # a fingerprint can say yes or no and nothing else

    with tempfile.TemporaryDirectory() as tmp:
        verdict = Path(tmp) / "verdict"
        proc = await asyncio.create_subprocess_exec(
            "/usr/bin/open", "-W", "-a", str(app), "--args", prompt, str(verdict),
            stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL,
        )
        try:
            await asyncio.wait_for(proc.wait(), timeout=CONFIG.local_timeout_seconds)
        except asyncio.TimeoutError:
            proc.kill()
            await proc.wait()
            return None
        if not verdict.exists():
            return None
        code = verdict.read_text().strip()

    if code == "0":
        return "yes"
    if code == "1":
        return "no"
    return None  # 2 = biometrics unavailable, so let another channel answer


def _as_applescript_string(text: str) -> str:
    """AppleScript string literal. The prompt carries a requester name and a reason that came in
    over the wire, so it is not something to paste into a script unescaped."""
    escaped = text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ")
    return f'"{escaped}"'


async def system_dialog(request: Request, prompt: str) -> str | None:
    """A real macOS dialog, drawn on the workstation.

    This is the channel that gets noticed. Elicitation puts the question inside the terminal that
    asked, which is invisible if you are not looking at that terminal — and if the agent is on the
    mac mini, that terminal may not even be on this desk. The dialog is drawn by the broker, so it
    lands where the human is regardless of who asked.

    Unlike LocalAuthentication, which this machine refuses to present at all, osascript dialogs
    come up fine from a launchd agent.
    """
    title = _as_applescript_string("Ask")
    body = _as_applescript_string(prompt)
    timeout = CONFIG.local_timeout_seconds

    if request.kind == "choose" and request.options:
        options = ", ".join(_as_applescript_string(o) for o in request.options)
        script = (
            f"tell application \"System Events\"\n activate\n"
            f" set picked to choose from list {{{options}}} with title {title}"
            f" with prompt {body}\n"
            f" if picked is false then return \"\"\n return item 1 of picked\nend tell"
        )
    elif request.kind == "ask_text":
        script = (
            f"tell application \"System Events\"\n activate\n"
            f" set r to display dialog {body} default answer \"\" with title {title}"
            f" giving up after {timeout}\n"
            f" if gave up of r then return \"\"\n return text returned of r\nend tell"
        )
    else:
        script = (
            f"tell application \"System Events\"\n activate\n"
            f" set r to display dialog {body} buttons {{\"Deny\", \"Approve\"}}"
            f" default button \"Approve\" with title {title} with icon caution"
            f" giving up after {timeout}\n"
            f" if gave up of r then return \"\"\n return button returned of r\nend tell"
        )

    proc = await asyncio.create_subprocess_exec(
        "/usr/bin/osascript", "-e", script,
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
    )
    try:
        out, _ = await asyncio.wait_for(proc.communicate(), timeout=timeout + 10)
    except asyncio.TimeoutError:
        proc.kill()
        await proc.wait()
        return None
    if proc.returncode != 0:
        return None

    answer = out.decode().strip()
    if not answer:
        return None  # gave up or cancelled: not an answer, so let the phone have it
    if request.kind in ("approve", "login_fill", "native_login_fill"):
        return "yes" if answer == "Approve" else "no"
    return answer


async def ask_human(ctx: Context, request: Request) -> str | None:
    """Local first, then the phone. Returns the raw answer, or None if nobody answered.

    Elicitation blocks forever by default, so the timeout lives here rather than in the caller.
    """
    audit("request", id=request.id, kind=request.kind, domain=request.domain,
          fields=request.fields, requester=request.requester)

    prompt = f"{request.prompt}\n(from {request.requester})"

    answered = await touch_id(request, prompt)
    if answered is not None:
        audit("answered", id=request.id, via="touch-id")
        return answered

    answered = await system_dialog(request, prompt)
    if answered is not None:
        audit("answered", id=request.id, via="dialog")
        return answered

    # Elicitation stays as the fallback: it is what works if osascript ever cannot draw, and it is
    # the nicer place to answer when you happen to be looking at the terminal anyway.
    try:
        result = await asyncio.wait_for(
            ctx.elicit(message=prompt, schema=_schema_for(request.kind)),
            timeout=CONFIG.local_timeout_seconds,
        )
        answer = _elicit_answer(result)
        if answer is not None:
            audit("answered", id=request.id, via="elicitation")
            return answer
    except asyncio.TimeoutError:
        pass  # nobody at the terminal; the phone gets it
    except Exception as exc:
        # A client that does not implement elicitation is expected; anything else is worth a line
        # in the log rather than silence.
        audit("elicitation.failed", id=request.id, error=type(exc).__name__)

    if MATRIX.configured:
        answer = await MATRIX.ask(request, CONFIG.remote_timeout_seconds)
        if answer is not None:
            audit("answered", id=request.id, via="matrix")
            return answer

    audit("unanswered", id=request.id)
    return None


def _elicit_answer(result: Any) -> str | None:
    """Map an elicitation result onto the same string an answer from any other channel would be.

    Declining is an answer — a no — while cancelling is not, and should fall through to the phone
    rather than be recorded as a refusal.
    """
    action = getattr(result, "action", None)
    if action == "decline":
        return "no"
    if action != "accept":
        return None
    data = getattr(result, "data", None)
    if isinstance(data, YesNo):
        return "yes" if data.approved else "no"
    if isinstance(data, Choice):
        return data.choice
    if isinstance(data, FreeText):
        return data.text
    return None


def is_yes(answer: str | None) -> bool:
    return (answer or "").strip().lower() in {"y", "yes", "ok", "approve", "はい", "承認"}


# ----------------------------------------------------------------------------------- filling in


def host_matches(url: str, domain: str) -> bool:
    """Does this URL belong to the domain being asked about?

    Exact host or a subdomain of it. Suffix comparison alone would let `evil-google.com` pass for
    `google.com`, so the dot is part of the test.
    """
    import urllib.parse

    host = (urllib.parse.urlsplit(url).hostname or "").lower()
    wanted = domain.lower().lstrip(".")
    return host == wanted or host.endswith("." + wanted)


def pick_target(targets: list[dict[str, Any]], domain: str) -> dict[str, Any]:
    """Choose the page to type into, by domain and never by position.

    One CDP endpoint can front several pages — this machine had a SlimeVR GUI and a mocopi preview
    sitting alongside the login — so taking the first one means typing a password into whatever
    happens to be there. Ambiguity is refused rather than guessed.
    """
    matches = [
        t
        for t in targets
        if t.get("type") == "page"
        and t.get("webSocketDebuggerUrl")
        and host_matches(t.get("url", ""), domain)
    ]
    if not matches:
        raise RuntimeError(f"no open page on {domain}")
    if len(matches) > 1:
        raise RuntimeError(f"{len(matches)} pages open on {domain}; close all but one")
    return matches[0]


async def fill_via_cdp(cdp_port: int, values: dict[str, str], domain: str) -> None:
    """Type values into the page over CDP.

    Not through argv: `ps` shows another process's arguments to the same user, so passing a
    password on a command line leaks it for the lifetime of that command. The websocket frame does
    not appear anywhere a bystander can read.

    `values` maps an element ref's objectId-producing selector to the text to put in it.
    """
    import urllib.request

    import websockets

    # The socket to talk to is the page target's own, listed by the CDP HTTP endpoint. There is no
    # generic /devtools/page path to connect to.
    targets = json.loads(
        urllib.request.urlopen(f"http://127.0.0.1:{cdp_port}/json/list", timeout=10).read()
    )
    target = pick_target(targets, domain)

    async with websockets.connect(target["webSocketDebuggerUrl"], max_size=None) as ws:
        counter = 0

        async def call(method: str, params: dict[str, Any]) -> dict[str, Any]:
            nonlocal counter
            counter += 1
            await ws.send(json.dumps({"id": counter, "method": method, "params": params}))
            while True:
                message = json.loads(await ws.recv())
                if message.get("id") == counter:
                    return message

        for selector, value in values.items():
            await call(
                "Runtime.evaluate",
                {
                    "expression": (
                        "(() => { const el = document.querySelector(%s);"
                        " if (!el) return false;"
                        " const setter = Object.getOwnPropertyDescriptor("
                        "   el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype"
                        "   : HTMLInputElement.prototype, 'value').set;"
                        " setter.call(el, %s);"
                        " el.dispatchEvent(new Event('input', {bubbles: true}));"
                        " el.dispatchEvent(new Event('change', {bubbles: true}));"
                        " return true; })()"
                        % (json.dumps(selector), json.dumps(value))
                    ),
                    "returnByValue": True,
                },
            )


def terminal_browser_cdp_port() -> int | None:
    """terminal-browser's CDP port changes every launch, so it is discovered rather than fixed.

    `ls --json` answers with {"self": ..., "browsers": [{"cdpPort": ...}]} — the port is nested,
    which the first version of this missed and reported "no browser with an open CDP port" while
    a browser was sitting right there.
    """
    tb = shutil.which("terminal-browser")
    if not tb:
        return None
    out = subprocess.run([tb, "ls", "--json"], capture_output=True, text=True)
    try:
        data = json.loads(out.stdout)
    except json.JSONDecodeError:
        return None
    for browser in data.get("browsers", []):
        if browser.get("cdpPort"):
            return int(browser["cdpPort"])
    return None


LOGIN_FIELDS = {"username", "password", "totp"}
NATIVE_HELPER_ERRORS = {
    "invalid request",
    "native application did not respond",
    "configured application is not frontmost",
    "focused element is not an editable text field",
    "Accessibility permission is unavailable",
    "macOS Accessibility fill failed",
}


def native_target(domain: str, target_name: str, bundle_id: str) -> dict[str, Any] | None:
    """Return a configured target only when this exact app/domain pairing is allowed."""
    target = CONFIG.native_targets.get(target_name)
    if not isinstance(target, dict):
        return None
    apps = target.get("apps", {})
    if not isinstance(apps, dict):
        return None
    domains = apps.get(bundle_id, ())
    if not isinstance(domains, list):
        return None
    return target if domain in domains else None


def native_input_mode(target: dict[str, Any], bundle_id: str) -> str:
    """Use keyboard input only for bundles explicitly named by the trusted broker config."""
    bundles = target.get("keystroke_bundles", ())
    if isinstance(bundles, list) and bundle_id in bundles:
        return "keystroke"
    return "ax_value"


def sanitize_native_result(result: Any) -> dict[str, Any]:
    """Keep a compromised remote helper from smuggling a credential back to the MCP caller."""
    if not isinstance(result, dict) or not isinstance(result.get("filled"), bool):
        return {"filled": False, "error": "native helper returned an invalid response"}
    if result["filled"]:
        return {"filled": True}
    error = result.get("error")
    if error not in NATIVE_HELPER_ERRORS:
        error = "native helper failed"
    return {"filled": False, "error": error}


async def fill_native_target(
    target: dict[str, Any], bundle_id: str, value: str, input_mode: str
) -> dict[str, Any]:
    """Run the fixed native helper locally or over SSH, sending the secret only on stdin."""
    helper = Path.home() / ".local/bin/ask-native-fill"
    ssh_target = target.get("ssh_target", "")
    if ssh_target:
        identity = Path(target.get("identity_file", "~/.ssh/id_automation")).expanduser()
        command = [
            "/usr/bin/ssh",
            "-F", "/dev/null",
            "-o", "IdentityAgent=none",
            "-o", "IdentitiesOnly=yes",
            "-o", "BatchMode=yes",
            "-o", "ClearAllForwardings=yes",
            "-i", str(identity),
            ssh_target,
            "/usr/bin/python3", ".local/bin/ask-native-fill",
        ]
    else:
        command = ["/usr/bin/python3", str(helper)]

    proc = await asyncio.create_subprocess_exec(
        *command,
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL,
    )
    payload = json.dumps(
        {"bundle_id": bundle_id, "input_mode": input_mode, "value": value}
    ).encode()
    try:
        stdout, _ = await asyncio.wait_for(proc.communicate(payload), timeout=25)
    except asyncio.TimeoutError:
        proc.kill()
        await proc.wait()
        return {"filled": False, "error": "native fill timed out"}
    try:
        result = json.loads(stdout)
    except json.JSONDecodeError:
        return {"filled": False, "error": "native helper returned an invalid response"}
    # A remote same-user process can replace the helper. Never relay arbitrary helper text to the
    # MCP caller, because it could put the credential in an added JSON field or error string.
    return sanitize_native_result(result)


# ------------------------------------------------------------------------------------ mcp server

mcp = FastMCP("ask")


@mcp.tool()
async def approve(ctx: Context, reason: str, requester: str = "unknown") -> dict[str, bool]:
    """Ask the human to approve something. Returns {"approved": bool}."""
    request = Request(kind="approve", prompt=reason, requester=requester)
    answer = await ask_human(ctx, request)
    approved = is_yes(answer)
    audit("outcome", id=request.id, approved=approved)
    return {"approved": approved}


@mcp.tool()
async def choose(ctx: Context, prompt: str, options: list[str], requester: str = "unknown") -> dict[str, str | None]:
    """Ask the human to pick one of `options`. Returns {"chosen": str | None}."""
    request = Request(kind="choose", prompt=prompt, options=options, requester=requester)
    answer = await ask_human(ctx, request)
    chosen = answer if answer in options else None
    audit("outcome", id=request.id, chosen=chosen)
    return {"chosen": chosen}


@mcp.tool()
async def ask_text(ctx: Context, prompt: str, requester: str = "unknown") -> dict[str, str | None]:
    """Ask the human for free text. Returns {"text": str | None}."""
    request = Request(kind="ask_text", prompt=prompt, requester=requester)
    answer = await ask_human(ctx, request)
    audit("outcome", id=request.id, answered=answer is not None)
    return {"text": answer}


@mcp.tool()
async def login_fill(
    ctx: Context,
    domain: str,
    selectors: dict[str, str],
    requester: str = "unknown",
) -> dict[str, Any]:
    """Fill a login form for `domain` after the human approves.

    `selectors` maps a field name to a CSS selector on the page, e.g.
    `{"username": "#login_field", "password": "#password"}`. Valid field names are the ones `bw`
    knows: username, password, or totp.

    Returns {"filled": bool}. **It never returns the values it typed**, and there is no other tool
    that does.
    """
    if domain not in CONFIG.allowed_domains:
        audit("refused", domain=domain, reason="not in allowlist", requester=requester)
        return {"filled": False, "error": f"{domain} is not in the allowlist"}

    unknown = set(selectors) - LOGIN_FIELDS
    if unknown:
        return {"filled": False, "error": "unsupported credential field"}

    wanted = list(selectors.keys())

    # Which account? More than one item on a domain is ordinary, and picking for the human would
    # be guessing with their credentials. So the choice replaces the yes/no: choosing is the
    # approval. A fingerprint cannot express a choice, so these land on the dialog.
    try:
        candidates = VAULT.candidates(domain)
    except RuntimeError as exc:
        audit("outcome", domain=domain, filled=False, reason=str(exc))
        return {"filled": False, "error": str(exc)}

    if not candidates:
        audit("outcome", domain=domain, filled=False, reason="no vault item")
        return {"filled": False, "error": f"no vault item matches {domain}"}

    if len(candidates) == 1:
        item_id, item_name = candidates[0]
        request = Request(
            kind="login_fill",
            prompt=f"Release {', '.join(wanted)} for {domain} ({item_name})?",
            requester=requester,
            domain=domain,
            fields=wanted,
        )
        answer = await ask_human(ctx, request)
        approved = is_yes(answer)
    else:
        names = [name for _, name in candidates]
        request = Request(
            kind="choose",
            prompt=f"Which account for {domain}? Releasing {', '.join(wanted)}.",
            options=names,
            requester=requester,
            domain=domain,
            fields=wanted,
        )
        answer = await ask_human(ctx, request)
        approved = answer in names
        if approved:
            item_id, item_name = candidates[names.index(answer)]

    if not approved:
        audit("outcome", id=request.id, approved=False)
        return {"filled": False, "error": "not approved"}

    port = terminal_browser_cdp_port()
    if port is None:
        return {"filled": False, "error": "no browser with an open CDP port"}

    # TOTP after the approval, never before: a code lives thirty seconds and a round trip to a
    # phone eats most of that.
    try:
        values = {
            selector: VAULT.get(field_name, item_id)
            for field_name, selector in selectors.items()
        }
    except RuntimeError as exc:
        audit("outcome", id=request.id, approved=True, filled=False, reason=str(exc))
        return {"filled": False, "error": str(exc)}

    try:
        await fill_via_cdp(port, values, domain)
    finally:
        values.clear()

    audit("outcome", id=request.id, approved=True, filled=True, domain=domain,
          fields=wanted, item=item_name)
    return {"filled": True}


@mcp.tool()
async def native_login_fill(
    ctx: Context,
    domain: str,
    target: str,
    bundle_id: str,
    field: str,
    requester: str = "unknown",
) -> dict[str, Any]:
    """Fill one focused field in an allowlisted native macOS app after human approval.

    `target` and `bundle_id` must match the broker's native target allowlist. `field` is one of
    username, password, or totp. The app must be frontmost with an editable field focused.
    Returns only {"filled": bool}; the credential is sent directly to the fixed helper on stdin.
    """
    if domain not in CONFIG.allowed_domains:
        audit("refused", domain=domain, reason="not in allowlist", requester=requester)
        return {"filled": False, "error": f"{domain} is not in the allowlist"}
    configured_target = native_target(domain, target, bundle_id)
    if configured_target is None:
        audit(
            "refused", domain=domain, target=target, bundle_id=bundle_id,
            reason="native target not in allowlist", requester=requester,
        )
        return {"filled": False, "error": "native app/domain target is not in the allowlist"}
    if field not in LOGIN_FIELDS:
        return {"filled": False, "error": "unsupported credential field"}

    try:
        candidates = VAULT.candidates(domain)
    except RuntimeError as exc:
        audit("outcome", domain=domain, filled=False, reason=str(exc))
        return {"filled": False, "error": str(exc)}
    if not candidates:
        audit("outcome", domain=domain, filled=False, reason="no vault item")
        return {"filled": False, "error": f"no vault item matches {domain}"}

    if len(candidates) == 1:
        item_id, item_name = candidates[0]
        request = Request(
            kind="native_login_fill",
            prompt=f"Release {field} for {domain} ({item_name}) into {bundle_id} on {target}?",
            requester=requester,
            domain=domain,
            fields=[field],
        )
        approved = is_yes(await ask_human(ctx, request))
    else:
        names = [name for _, name in candidates]
        request = Request(
            kind="choose",
            prompt=f"Which account for {domain}? Releasing {field} into {bundle_id} on {target}.",
            options=names,
            requester=requester,
            domain=domain,
            fields=[field],
        )
        answer = await ask_human(ctx, request)
        approved = answer in names
        if approved:
            item_id, item_name = candidates[names.index(answer)]

    if not approved:
        audit("outcome", id=request.id, approved=False)
        return {"filled": False, "error": "not approved"}

    value = ""
    try:
        value = VAULT.get(field, item_id)
        result = await fill_native_target(
            configured_target,
            bundle_id,
            value,
            native_input_mode(configured_target, bundle_id),
        )
    except RuntimeError as exc:
        result = {"filled": False, "error": str(exc)}
    finally:
        value = ""

    audit(
        "outcome", id=request.id, approved=True, filled=result["filled"], domain=domain,
        fields=[field], item=item_name, target=target, bundle_id=bundle_id,
    )
    return result


class RequireToken:
    """Bearer check in front of the MCP app.

    Off when no token file is configured, which keeps the loopback-only setup frictionless. It
    refuses to stay off once the broker is listening on anything but localhost: an open endpoint
    that hands out approval prompts is a way to make someone approve something by wearing them
    down.
    """

    def __init__(self, app: Any, token: str) -> None:
        self.app = app
        self.token = token

    async def __call__(self, scope: dict[str, Any], receive: Any, send: Any) -> None:
        if scope["type"] != "http" or not self.token:
            await self.app(scope, receive, send)
            return
        headers = dict(scope.get("headers") or [])
        presented = headers.get(b"authorization", b"").decode()
        if presented != f"Bearer {self.token}":
            audit("unauthorized", path=scope.get("path"))
            await send({"type": "http.response.start", "status": 401,
                        "headers": [(b"content-type", b"text/plain")]})
            await send({"type": "http.response.body", "body": b"unauthorized"})
            return
        await self.app(scope, receive, send)


def main() -> None:
    import uvicorn

    token = ""
    if CONFIG.token_file:
        token = Path(CONFIG.token_file).expanduser().read_text().strip()
    if not token and CONFIG.host not in ("127.0.0.1", "localhost", "::1"):
        raise SystemExit(
            f"refusing to listen on {CONFIG.host} without token_file: "
            "an endpoint anyone can reach must not be one anyone can ask through"
        )

    app = RequireToken(mcp.streamable_http_app(), token)
    uvicorn.run(app, host=CONFIG.host, port=CONFIG.port, log_level="info")


if __name__ == "__main__":
    main()
