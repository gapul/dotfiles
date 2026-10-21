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

A second instance runs on the mac mini itself, for the agents T3 Code starts there. The workstation
is a laptop and is often asleep exactly when the human is away and answering from a phone, so a
mac mini agent cannot depend on it. The mac mini has nobody in front of its screen, so that
instance asks over Matrix only (`channels`, below), and it holds its own vault session.

The agents there run as the same user as the broker, which shapes how that instance is set up:
whatever it reads from disk, they can read; whatever it reads from a writable file, they can
rewrite. So its config is a read-only store path, the master password is never written down — a
human runs `ask-unlock` over ssh and the session exists only in the broker's memory — and its
Matrix token belongs to a bot that can ask but not answer. What this does not stop is an agent
replacing the broker itself and waiting for the next `ask-unlock` to type the password into its
impostor. Only a separate user for the broker closes that; see Open.

## Requests

Six kinds. The first three return an answer; the two fill kinds return only whether it worked;
`run` returns what the command it ran printed.

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

**Which account.** More than one vault item on a domain is ordinary: a personal login and a work
one, on the same site. The broker does not pick. When several match, the approval becomes the
choice — the human is shown the account names and selects one, and selecting is the approval, so
it is still one gesture. A fingerprint cannot express a choice, so these land on the dialog.

Candidates are filtered by their login URIs rather than by `bw`'s search, which also matches names
and notes: a plain search for google.com returned ten items on this machine where four are real.
Host comparison is exact-or-subdomain, because plain suffix matching would let `evil-google.com`
answer for `google.com`.

The chosen account's name goes in the log. It is not a credential, and an audit trail that cannot
say which account was released is not much of one — but it does mean the log describes the vault,
which is worth knowing before pointing anything else at that file.

**There is no request that returns a credential to the caller.** Not "there is one but do not use
it": the broker has no code path that puts a secret in a response. This is the one rule the rest
of the design is arranged around, borrowed from `aac`, whose `connect` prints credentials and
whose `run` injects them — a distinction that is only a footnote until someone reads the wrong
docs at the wrong moment.

### native_login_fill

```
native_login_fill domain:str target:str bundle_id:str field:str → {filled: bool}
```

Fills one currently focused `AXTextField`, `AXSecureTextField`, or `AXTextArea` in an explicitly
allowlisted macOS application. The helper verifies the frontmost bundle identifier immediately
before writing and never presses Submit. A remote target such as the Mac mini is reached with a
fixed SSH destination and key from broker configuration; the secret travels only through SSH
stdin, never argv or an MCP response.

One field per request is deliberate. Multi-page native and embedded-browser login flows do not
keep username, password and TOTP fields alive at the same time, and filling a Tab-based sequence
would risk placing a later secret into the wrong control.

### run

```
run  domain:str  env:{VAR: field}  command:[str]  cwd:str  →  {ran, exit_code, stdout, stderr, timed_out, truncated}
```

Runs `command` (an argv list, no shell) in `cwd` on the broker's machine with the released fields
in its environment, e.g. `env = {"GH_TOKEN": "password"}`. This is the `spawn` arrow in the shape
above, and the same thing `aac run` does, with the approval coming from the channels here instead
of a terminal UI that only works for someone sitting at it.

**The human approves the command, not just the domain.** The prompt shows the exact argv — the
program resolved to an absolute path, and that path is what runs — and the directory with symlinks
resolved. Every character that does not print as itself is spelled out (`\n`, `\u{202e}`), so
blank lines or a direction override cannot push the real command out of view, and a command too
long to read is refused rather than shown cut. It is the command that decides where the value goes: `gh api user` uses it, `env` prints
it. For the same reason nothing carries over between runs — the login tools' three-minute window
does not apply, and every run is its own question.

**What comes back is the child's output, with the released values replaced by `[redacted]`.** This
bends the rule above, and the bend should be stated plainly: the broker still has no code path that
puts a secret in a response, but the child is a program the caller chose, and output is what it
chose to print. Scrubbing catches the accidental cases — `env`, a verbose flag, an error message
quoting the token. It cannot catch a command written to disguise the value first, and does not
try. That is what reading the command before approving is for.

Bounded, so a request cannot hold the broker indefinitely: the child is killed with everything it
spawned after `run_timeout_seconds`, and each stream is cut at `run_output_bytes`. The vault session
is never in the child's environment. The domain allowlist applies here as it does to the fill
tools, and so does the account choice: several matching items become a pick, and the pick is the
approval.

## Answering

The broker tries channels in order and takes the first answer.

1. **A dialog on the workstation.** Drawn by the broker with osascript, so it lands where the
   human is rather than wherever the request came from — which matters, because the agent that
   asked may be on the mac mini. It is also the only local channel that gets noticed: a question
   inside a terminal is invisible unless you happen to be looking at that terminal.
2. **Elicitation.** MCP elicitation (Claude Code 2.1.76+), as the fallback if osascript cannot
   draw, and the nicer place to answer when you are looking at the terminal anyway. It blocks
   indefinitely by default, so the timeout belongs here, not in the caller.
3. **Matrix.** Posts to a room on the self-hosted Conduit and waits for a reply. Element on the
   phone is the client. Reaches the human anywhere.

Which of these are tried is set by `channels` in the broker config, in the order above. The
headless mac mini instance lists only `matrix`: a dialog nobody can see would hold every request
for the full local timeout before the phone heard about it.

Only the configured `approver` can answer on Matrix, and only by replying to the question's own
message. The room is the boundary otherwise, and a room is something people get invited to. A plain
"yes" is ignored: it would answer every question waiting at that moment, including one raised next
to the one the human meant, and a late answer to a question that timed out would land on the next.
The broker posts with a bot account's token, never the approver's, and refuses to ask if the token
turns out to be the approver's own — the token file is readable by whatever runs as the same user,
and a token that can answer would let that answer itself. The broker reads messages over the plain
client API, so the room must not be end-to-end encrypted.

`run` is never answered by elicitation. Elicitation is answered by the client that made the call,
and for `run` that client is exactly the party the approval is meant to hold back.

Matrix is the remote channel today; a self-built
iOS/watchOS app talking to APNs directly is the intended replacement, because notification
actions from a native app are answerable from the watch itself, which mirrored third-party
notifications are not. Nothing above this layer should need to change when that lands.

Touch ID sits in front of all of them, for the yes-or-no kinds — a fingerprint can
say yes or no and nothing else, so `choose` and `ask_text` skip it. The policy is
`BiometricsOrCompanion`, so a paired Apple Watch satisfies it when a hand is not free. It falls
through to the dialog when biometrics are unavailable.

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

- Getting the Touch ID helper onto the machine declaratively. It cannot be built through nix here
  — nixpkgs' swift will not link LocalAuthentication, the wall the Apple Speech work documented —
  so it wants a CI build and a fetched release, the way terminal-browser already
  works. `helper/build.sh` in github.com/gapul/ask installs it by hand until then, and the broker
  skips the channel when the app is not there.
- The dialog stays on screen after the local timeout, because the elicitation and the osascript
  call are not cancelled when another channel wins. Answering a stale one does nothing.
- The mac mini instance runs as the agents' own user. Its setup keeps secrets off disk and its
  config read-only, but an agent can still stop the launchd job and listen on the port itself, then
  collect the master password from the next `ask-unlock`. Running the broker as its own macOS user,
  with `run` dropping to the agent's user for the child, is the fix. Until then, an unexpected
  "locked" is a reason to look at what is listening before unlocking.
- Known and accepted for now (2026-10-14): the mac mini holds a token for @gapul:gapul.net — the
  approver, and a Synapse server admin — at ~/.config/matrix/gapul_token, readable by the agents
  there. With it an agent can reply "yes" to its own question, or mint a token for any account,
  so Matrix approval is no barrier to an agent on the mac mini that goes looking. Closing it means
  moving server admin to an account whose token is not on that machine and approving from a
  dedicated account, or verifying replies by their E2EE device signature.
- The mac mini as a native target: the broker holds the vault on the workstation and the secret
  crosses an SSH connection over the tailnet to a fixed helper. Same-user isolation on the far
  end is no better than it is here, which is to say weak, and no amount of protocol fixes it.
- Sessions in `terminal-browser` are split across seven directories on this machine, so a login
  performed once does not necessarily survive. Unrelated to this protocol, but it is the reason a
  passkey-only site cannot fall back to "just stay logged in" yet.
