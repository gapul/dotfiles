# CodexBar configuration

This is the real `~/.config/codexbar/config.json`, linked in as an out-of-store symlink, so
anything changed through CodexBar's UI is written straight back here. Handled the same way as
[omniwm](../../wm/omniwm/README.md).

The wiring is in `nix/home/darwin.nix`, so a rebuild on a new Mac creates the link.

`providers[].codexActiveSource` holds the UUID of the Codex account. This repository is public,
but that is an identifier rather than a credential, so it stays tracked.
