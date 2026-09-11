# claude-agent

Automatic fixes and reviews, resident on the headless mac mini. When an issue is opened, when a
GitHub Actions run fails, or when a pull request appears, Claude Code on the mini opens a fixing
pull request or leaves a review.

This replaces the auto-fix pipeline that used to live only in `mugen404/prod-record`. That one was
tied to a single repository, and by 2026-09 it had been dead for over a day without anyone noticing:
the mini's Claude Code was not authenticated, the monitor ran as root so `claude` refused
`--dangerously-skip-permissions`, and the runner it was watching had been unregistered.

## How it is put together

`claude-agent.sh` is the only entry point, reachable as `~/.local/bin/claude-agent`. The files sit
in the nix store, so the way to change the agent is to edit this repository and rebuild — what is
running cannot be edited in place.

| File | What it does |
|---|---|
| `repos.json` | The allowlist. A repository not listed here is never touched. |
| `lib.sh` | Environment, auth, locking, the record of what has been handled, working copies. |
| `run-autofix.sh` | Implements an issue, or repairs a failed Actions run, then opens a PR. |
| `run-review.sh` | Reviews a pull request with inline comments and suggestions. |
| `poller.sh` | Walks `repos.json` every five minutes and dispatches to the two above. |
| `monitor.sh` | Checks once an hour that the agent itself is still working. |

Work reaches the agent two ways. A repository can carry a ten-line caller workflow that calls
`gapul/dotfiles/.github/workflows/claude-agent.yml`, which runs on the self-hosted runner on this
same machine and reacts immediately. Everything else is found by the poller. Both share one record
of what has been handled, so arriving twice does not mean acting twice.

## The boundaries

Reviewing other people's pull requests means putting a fork's code on this machine. Building or
testing that code is the same thing as executing it, so `run-review.sh` is the one place `claude`
runs read-only (`--allowedTools "Read,Grep,Glob"`). Reviews never push to someone else's branch and
never submit `REQUEST_CHANGES` or `APPROVE` — a bot should not be able to block a person's pull
request. For the same reason review is not triggered from Actions at all: that would need
`pull_request_target`, which puts a write-capable token on a self-hosted runner at a stranger's
request.

Fixing runs with full permissions, but only inside repositories listed in `repos.json`, and only on
branches that exist on `origin`.

## Stopping it

- Label an issue or pull request `no-claude` to stop it for that one thing.
- `claude-agent pause` writes `~/.local/state/claude-agent/PAUSE` and stops everything.
  `claude-agent resume` removes it. The monitor complains if it stays for more than a day.
- Remove the repository from `repos.json` to stop it permanently.

`CLAUDE_AGENT_DRY_RUN=1` posts and pushes nothing and only logs what would have happened. The first
pass against a new repository is always a dry one regardless: it records what already exists so the
agent does not wake up to a backlog of open issues and react to all of them at once.

## Things that catch you out

**`LANG` has to be set.** launchd gives you an empty locale, and bash then swallows the multi-byte
character following a variable reference into the variable's name: `$ts。` becomes
`ts。: unbound variable` and the script dies under `set -u`.

**These have to be home-manager LaunchAgents, not system ones.** nix-darwin's system-level
`launchd.agents` land in `/Library/LaunchAgents` and start in a root context on a machine with no
GUI login, and `claude` refuses `--dangerously-skip-permissions` under root.

**Auth is a file, not the keychain.** `~/.config/claude/oauth-token` is placed by sops from
`claude_code_oauth_token` in `secrets/common.yaml`. Mint it with `claude setup-token` in an
interactive session. When it expires everything quietly stops doing anything, so `run_claude` looks
for "Not logged in" in the output and notifies.

**`gh auth token` sometimes returns empty.** An empty `GH_TOKEN` takes precedence over `hosts.yml`,
so every later `gh` call runs unauthenticated. It is only exported when non-empty.

**Infrastructure failures are not code failures.** A dead runner, a broken network, a rate limit or
a full disk cannot be fixed by changing code, so those are matched by pattern and turned into a
notification instead of a claude run.
