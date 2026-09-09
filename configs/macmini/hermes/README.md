# hermes

The parts of the Hermes agent on the mac mini — running as a dedicated user, `hermes`, with its
sandbox as `hsandbox` — that were written here. No configuration and no secrets.

## claude-acp, moved to its own repository

Hermes's `copilot-acp` provider spawns an external process and speaks JSON-RPC 2.0 over stdio.
`claude-acp` is a minimal adapter for the other end of that: it takes `session/prompt`, calls
`claude -p` on the subscription, and passes the answer straight back. That makes Claude the
inference backend without paying for Anthropic's API.

The inner `claude` runs with tools disabled. Executing tools is Hermes's job, and Hermes handles
the `<tool_call>` blocks in the reply through its own tool layer.

The code now lives in [gapul/claude-acp](https://github.com/gapul/claude-acp). It is a component
for running Hermes rather than a setting for this machine, so dotfiles has no reason to hold it.
It is referenced here as a flake input, and the activation in `nix/hosts/macmini.nix` lays it
down from the store at `/Users/hermes/.local/bin/claude-acp` — home-manager cannot reach another
user's home. `HERMES_COPILOT_ACP_COMMAND` in `.env` points at that path.

### What is added only on the manabi side, when HOME is `manabi-home`

- **Prefix every turn with the date and time.** The inner `claude` only receives the date, so
  asked for the time it guesses, and in practice was an hour and a half out. The day of the week
  is passed too, to stop it miscounting.
- **Call the sandbox's `~/study/after_turn.py` after each exchange.** That commits the study
  record to git on the far side and, if the plan changed and there is no image, generates one
  and returns `MEDIA:`. The image is attached only when the reply contains `MEDIA:`, but the
  call happens every time because the commit should. If the script is missing it quietly does
  nothing, so one side being out of date does not break anything.

This is fragile. What the implementation matches is the contract in Hermes's internal
`agent/copilot_acp_client.py`, which is not a public API. After upgrading Hermes, always check
that a conversation still goes through.

## manabi, moved to its own repository

The whole study tutor now lives in [gapul/manabi](https://github.com/gapul/manabi), which is
private: the gateway's startup shim, the dashboard, the sandbox scripts, SOUL and the channel
prompts. On this machine it is cloned at `/Users/Shared/manabi`, and the launchd units exec from
there. Being private it cannot be a flake input, since CI could not fetch it, hence the path
reference. Updating the service is a `git pull` over there; no dotfiles rebuild is involved.

## What is deliberately not here

`config.yaml`, in `/Users/hermes/.hermes/` and `/Users/hermes/manabi-home/.hermes/`, is
rewritten by Hermes while it runs. Keeping it in git would mean a permanent diff, and the
manabi one holds Discord channel IDs and someone's actual study record, which does not belong in
a public repository.

`.env`, holding the tokens, is absent for the same reason.

## What was removed

`claude-bridge`, the old path that called `claude -p` through an OpenAI-compatible endpoint on
:9180, was removed on 2026-08-12. Nothing had used it since `model.provider` moved to
`copilot-acp`; the last inference it served was on 2026-07-17. It also depended on the claude
binary in gapul's home, which was one of the things preventing proper user separation. To bring
it back, reinstall niski84/claude-bridge, enable the `model-providers/claude-cli` plugin and set
`model.provider: claude-cli`.
