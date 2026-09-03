# Claude Code

Held differently on the Mac and on remote machines reached through nssh.

## On the Mac, symlinked wholesale

`nix/home/workstation.nix` creates out-of-store symlinks, so the files here are the real thing.

| The real file | Linked to |
| --- | --- |
| `settings.json` | `$CLAUDE_CONFIG_DIR/settings.json` |
| `CLAUDE.md` | `$CLAUDE_CONFIG_DIR/CLAUDE.md` |
| `hooks/`, `output-styles/`, `bin/` | The directories of the same name |
| `skills/{english-vocab,gapul-writing-voice,step-by-step-tutor}` | Under `skills/` |

Keeping the whole `settings.json` works because the Mac runs with
`defaultMode: bypassPermissions`, so `permissions.allow` never grows. Anything the TUI writes
back lands in this file, and when it shows up in `git diff` it can simply be committed.

Session history, `.claude.json`, which holds credentials, and `settings.local.json` are state
and are not kept. Vendored skills, such as cloudflare's, can be fetched again from upstream and
are not managed either.

## On remote machines, merging only the managed keys

`scripts/merge-claude-settings.py` merges only the managed keys from `settings.remote.json`
over whatever JSON the host already has. It is the same idea as adding a single line to
`~/.bashrc` that sources `bashrc.remote`: anything unmanaged stays as the host had it.

| | Keys |
| --- | --- |
| Managed | `permissions.defaultMode`, `theme`, `effortLevel`, `editorMode`, `verbose`, `preferredNotifChannel`, `skipDangerousModePermissionPrompt`, `skipWorkflowUsageWarning`, `environmentVariables` |
| Unmanaged, owned by the host | `permissions.allow`, `permissions.additionalDirectories`, `enabledPlugins`, `hooks` |

The managed set is limited to keys the Mac's own `settings.json` actually contains.
Distributing a key the Mac does not set would leave the Mac on the default while the remote had
an explicit value, which breaks the rule below that the Mac is authoritative. `tui`,
`inputNeededNotifEnabled` and `agentPushNotifEnabled` had been lifted from a remote machine's
values rather than the Mac's, and were removed on 2026-08-13. The values already distributed
stay where they are, and are treated as host-owned from now on.

### Why not symlink it the way the Mac does

Once `defaultMode: bypassPermissions` was distributed, `permissions.allow` stopped growing, so
the original reason — that symlinking would wipe accumulated approvals every time — went away
on 2026-08-15. It stays a merge because the Mac's `settings.json` contains keys that either
break or mean nothing on a remote machine.

- `hooks` — absolute paths like `/Users/gapul/.config/claude/hooks/*.sh`, which do not exist on
  Linux and fail every time. Remote machines have their own hooks, integrated with herdr.
- `enabledPlugins` — the Mac has clangd and the Swift LSP. What a given box needs is
  rust-analyzer, and distributing this would replace it. Toolchains differ per host, so it is
  left alone.
- `extraKnownMarketplaces` — only meaningful together with those plugins, so it goes too.
- `disableDeepLinkRegistration` — a macOS `~/Applications` URL handler thing, with no Linux
  equivalent.
- `defaultModel` — the Mac pins `claude-sonnet-4-20250514`. Distributing it would roll the
  remote's default model back too. Leaving it out is deliberate; if they should match, revisit
  the pin on the Mac first rather than adding it here.

### Nesting

Only `defaultMode` inside `permissions` is managed. The merge recurses only where both sides
have an object, so `allow` and `additionalDirectories` as the host grew them survive. Arrays are
not recursed into, since merging `allow` element by element is not the intent. `--check` and
`--adopt` follow the same structure.

### What distributing bypassPermissions means

Claude Code runs on the remote machine without asking for permission. On a shared machine, use
it on the understanding that whatever Claude is allowed to do there is everything your account
can do.

`CLAUDE.md` and the hand-written skills are never rewritten, so they are symlinked on remote
machines as normal. `hooks/`, `output-styles/` and `bin/` assume the Mac's desktop —
notifications through osascript, herdr, the Notion MCP — and are not carried across.

Never point this script at the Mac's own `settings.json`. It writes through a temporary file and
a rename, which would replace the symlink nix created with a real file and break tracking. On
the Mac, use it only in the `--adopt` direction, which just reads.

## Which side wins: the client machine

For the managed keys, the Mac you connect from is authoritative. Changing a setting on a remote
machine is temporary, local to that host, and gets overwritten by the next merge. Updates travel
in the other direction, pulled up from the Mac:

```
just claude-settings-adopt     # pull the Mac's current values into settings.remote.json
```

It pulls only the managed keys `settings.remote.json` already has; the set never grows, so that
`permissions` is not swept in. To manage a new key, add it to `settings.remote.json` by hand
first, then run `adopt`.

## theme = auto, and following light and dark

`auto` appears in the TUI as "Auto (match terminal)", and it watches the terminal rather than
the OS. It sends OSC 11 to ask for the background colour, reads the `rgb:RRRR/GGGG/BBBB` reply,
and falls back to `COLORFGBG` when there is no answer.

That means it follows correctly even over ssh, because what answers is ghostty on the Mac.
Claude needs neither the two dark and light endpoints in `nix/lib/theme.nix` nor a side channel
like `theme-watch`.

Inside tmux, though, tmux itself answers the OSC 11, so whether the query reaches the outer
ghostty depends on the tmux version. This is the same constraint nvim's automatic `&background`
detection has; see the comments about OSC 111 in
`configs/editors/nvim/lua/plugins/auto-dark-mode.lua`.

## Applying it

- On the Mac: `just rebuild`
- On a remote machine: `nssh <host>`
- By hand: `python3 scripts/merge-claude-settings.py ~/.claude/settings.json`
