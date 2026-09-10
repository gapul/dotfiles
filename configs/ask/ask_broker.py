#!/usr/bin/env python3
"""ask broker — the thing that holds the vault session and asks the human.

Protocol: docs/ask-protocol.md in the dotfiles repo. Read that first; this file implements it and
does not restate the reasoning.

Runs on the workstation as a launchd agent in the GUI session, and listens on the tailnet so that
an agent working on the mac mini reaches the same broker.

The single rule this file is arranged around: **no code path returns a credential to the caller.**
`login_fill` types values into a browser and answers whether that worked. There is deliberately no
`get_password`, not even a private one.
"""

from __future__ import annotations

import asyncio
import json
import os
import shutil
import subprocess
import time
import tomllib
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Literal

from mcp.server.fastmcp import Context, FastMCP

CONFIG_PATH = Path(os.environ.get("ASK_CONFIG", Path.home() / ".config/ask/broker.toml"))


# --------------------------------------------------------------------------------------- config


@dataclass(frozen=True)
class Config:
    host: str = "127.0.0.1"
    port: int = 8933

    # Only these domains can ever be the subject of login_fill. An approval for anything else is
    # refused before the vault is touched, which is what bounds a mistaken or forged approval.
    allowed_domains: tuple[str, ...] = ()

    # Re-lock the vault after this long without a release. A leaked session key expires.
    vault_idle_seconds: int = 900

    # How long the person at the terminal gets before the question goes to their phone.
    local_timeout_seconds: int = 25
    remote_timeout_seconds: int = 600

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
            vault_idle_seconds=broker.get("vault_idle_seconds", cls.vault_idle_seconds),
            local_timeout_seconds=broker.get("local_timeout_seconds", cls.local_timeout_seconds),
            remote_timeout_seconds=broker.get("remote_timeout_seconds", cls.remote_timeout_seconds),
            vault_password_file=broker.get("vault_password_file", ""),
            token_file=broker.get("token_file", ""),
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
    kind: Literal["approve", "choose", "ask_text", "login_fill"]
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
        if request.kind in ("approve", "login_fill"):
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


async def ask_human(ctx: Context, request: Request) -> str | None:
    """Local first, then the phone. Returns the raw answer, or None if nobody answered.

    Elicitation blocks forever by default, so the timeout lives here rather than in the caller.
    """
    audit("request", id=request.id, kind=request.kind, domain=request.domain,
          fields=request.fields, requester=request.requester)

    prompt = f"{request.prompt}\n(from {request.requester})"

    try:
        result = await asyncio.wait_for(
            ctx.elicit(message=prompt, schema=None),
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
    """FastMCP's elicitation result shape varies by SDK version; accept the plausible ones."""
    action = getattr(result, "action", None)
    if action in ("decline", "cancel"):
        return "no"
    content = getattr(result, "content", None)
    if isinstance(content, dict):
        for key in ("answer", "text", "value", "choice"):
            if key in content:
                return str(content[key])
    if isinstance(content, str):
        return content
    if action == "accept":
        return "yes"
    return None


def is_yes(answer: str | None) -> bool:
    return (answer or "").strip().lower() in {"y", "yes", "ok", "approve", "はい", "承認"}


# ----------------------------------------------------------------------------------- filling in


async def fill_via_cdp(cdp_port: int, values: dict[str, str]) -> None:
    """Type values into the page over CDP.

    Not through argv: `ps` shows another process's arguments to the same user, so passing a
    password on a command line leaks it for the lifetime of that command. The websocket frame does
    not appear anywhere a bystander can read.

    `values` maps an element ref's objectId-producing selector to the text to put in it.
    """
    import websockets

    async with websockets.connect(f"ws://127.0.0.1:{cdp_port}/devtools/page", max_size=None) as ws:
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
    """terminal-browser's CDP port changes every launch, so it is discovered rather than fixed."""
    tb = shutil.which("terminal-browser")
    if not tb:
        return None
    out = subprocess.run([tb, "ls", "--json"], capture_output=True, text=True)
    try:
        data = json.loads(out.stdout)
    except json.JSONDecodeError:
        return None
    entries = data if isinstance(data, list) else [data]
    for entry in entries:
        if entry.get("cdpPort"):
            return int(entry["cdpPort"])
    return None


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
    knows: username, password, totp, uri.

    Returns {"filled": bool}. **It never returns the values it typed**, and there is no other tool
    that does.
    """
    if domain not in CONFIG.allowed_domains:
        audit("refused", domain=domain, reason="not in allowlist", requester=requester)
        return {"filled": False, "error": f"{domain} is not in the allowlist"}

    wanted = list(selectors.keys())
    request = Request(
        kind="login_fill",
        prompt=f"Release {', '.join(wanted)} for {domain}?",
        requester=requester,
        domain=domain,
        fields=wanted,
    )

    answer = await ask_human(ctx, request)
    if not is_yes(answer):
        audit("outcome", id=request.id, approved=False)
        return {"filled": False, "error": "not approved"}

    port = terminal_browser_cdp_port()
    if port is None:
        return {"filled": False, "error": "no browser with an open CDP port"}

    # TOTP after the approval, never before: a code lives thirty seconds and a round trip to a
    # phone eats most of that.
    try:
        values = {selector: VAULT.get(field_name, domain) for field_name, selector in selectors.items()}
    except RuntimeError as exc:
        audit("outcome", id=request.id, approved=True, filled=False, reason=str(exc))
        return {"filled": False, "error": str(exc)}

    try:
        await fill_via_cdp(port, values)
    finally:
        values.clear()

    audit("outcome", id=request.id, approved=True, filled=True, domain=domain, fields=wanted)
    return {"filled": True}


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
