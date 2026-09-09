# ask — protocol v0

A local service that lets an agent ask a human a question, and lets a human release one
credential to an agent, without the agent ever holding the secret.

Written before the implementation on purpose. The thing handles passwords, so the shape it
promises should be reviewable on its own, separately from whatever the code ends up doing.

## Why this exists

Two problems, one answer.

Handing an agent a password by pasting it into a chat puts the secret in a transcript, in
scrollback, and in whatever logs sit behind them. It is also tedious. The agent should be able to
say "log into github.com" and get a filled form back, never a string.

Separately, an agent working alone needs to ask things — approve this, pick one of these, what
should this say. Today that only works while a human is watching the terminal. Away from it, the
agent stalls.

Both are the same shape: the agent raises a request, a human answers it wherever they happen to
be, and the agent gets back only what it needs to continue.

## What it is not

Not a vault. Bitwarden stays the vault; this only asks `bw` for one item at a time.

Not a way to hold a session open for an agent. Every request is answered individually.

Not usable for passkeys. A passkey is a WebAuthn credential whose private key never leaves its
authenticator, so there is nothing to inject. This is treated as a feature: an account that is
passkey-only is one an agent structurally cannot enter, which makes it a useful boundary to draw
deliberately rather than a gap to work around. See "Passkeys" below.

## Shape

```
agent  ──request──▶  broker  ──ask──▶  human   (terminal, or Element on a phone)
                       │
                       ├── bw get ────▶  vault
                       └── spawn ─────▶  short-lived child holding the secret in its env
```

The broker runs on the workstation as a launchd agent in the GUI session. It listens on the
tailnet, not only on a unix socket, because agents also run on the mac mini when that is the dev
box, and the answer has to reach whichever machine asked.

## Requests

Four kinds. The first three return an answer; the last one returns only whether it worked.

### approve

```
approve  reason:str  →  {approved: bool}
```

### choose

```
choose   prompt:str  options:[str]  →  {chosen: str}
```

### ask_text

```
ask_text prompt:str  →  {text: str}
```

### login_fill

```
login_fill domain:str  fields:[str]  target:{...}  →  {filled: bool}
```

`fields` names what the request needs, e.g. `["password"]` or `["username", "password", "totp"]`.
A request that only needs a password does not get a TOTP. `target` says where the values go —
element refs from a page snapshot, in practice.

**There is no request that returns a credential to the caller.** Not "there is one but do not use
it": the broker has no code path that puts a secret in a response. This is the one rule the rest
of the design is arranged around, borrowed from `aac`, whose `connect` prints credentials and
whose `run` injects them — a distinction that is only a footnote until someone reads the wrong
docs at the wrong moment.

## Answering

The broker tries channels in order and takes the first answer.

1. **Elicitation.** MCP elicitation (Claude Code 2.1.76+) puts the question in front of whoever is
   at the terminal. Waits a short, bounded time — elicitation blocks indefinitely by default, so
   the timeout belongs here, not in the caller.
2. **Matrix.** Posts to a room on the self-hosted Conduit and waits for a reply. Element on the
   phone is the client. Reaches the human anywhere.

Channels are pluggable and ordered by config. Matrix is the remote channel today; a self-built
iOS/watchOS app talking to APNs directly is the intended replacement, because notification
actions from a native app are answerable from the watch itself, which mirrored third-party
notifications are not. Nothing above this layer should need to change when that lands.

Touch ID is wanted for the local case and is not specified yet: whether a launchd agent can raise
a `LocalAuthentication` prompt is unverified, and building the helper may run into the same
"cannot build Swift from nixpkgs" wall documented for the Apple Speech APIs. Elicitation covers
the local case until then.

## What the human sees

Every request shows, before anything is released:

- **what** — the reason, the options, or the domain and the exact fields being asked for
- **who** — which machine and which session raised it

The requester matters because agents run on more than one machine here. "github.com wants a
password" is not an answerable question; "the agent on macmini wants github.com's password" is.

## Layers

Beyond the approval itself, three things that hold even if an approval is wrongly given.

**Allowlist.** Only domains listed as agent-usable can ever be the subject of `login_fill`. An
approval for anything else fails before it reaches the vault. This bounds the damage of a forged
or mistaken approval to a set the human chose in advance.

**Session lifetime.** The broker re-locks `bw` after an idle period rather than holding an
unlocked vault forever. A leaked session key expires.

**Log.** Every request, its requester, its answer, and its outcome, appended. Secrets never
appear. This is what makes a failure of the other layers noticeable afterwards.

## TOTP

Generated after the approval returns, never before. A code is valid for thirty seconds and a
round trip to a phone can eat most of that; fetching it early produces expired codes and a
failure mode that reads like a wrong password.

## Passkeys

Out of scope, permanently as far as this protocol is concerned.

The FIDO Alliance formed an Agentic Authentication Technical Working Group in April 2026, with
Google's AP2 and Mastercard's Verifiable Intent as starting contributions, aimed at exactly this
gap: today's authentication assumes a human acting directly, and offers services no way to verify
that an agent acts within limits a user set. The work is early and aimed first at commerce.

Worth noting because the delegation model it describes — a human authorizing an agent for a
bounded action, verifiably — is the same shape as this document. If it lands, what changes is
what the human approves: signing a delegation rather than releasing a password. The requests, the
channels, and the layers above stay as they are.

## Open

- Touch ID from a launchd agent: unverified, see above.
- The mac mini as requester: the broker holds the vault on the workstation and the secret crosses
  the tailnet to the requesting machine. WireGuard covers the wire. Same-user isolation on the
  far end is no better than it is here, which is to say weak, and no amount of protocol fixes it.
- Sessions in `terminal-browser` are split across seven directories on this machine, so a login
  performed once does not necessarily survive. Unrelated to this protocol, but it is the reason a
  passkey-only site cannot fall back to "just stay logged in" yet.
