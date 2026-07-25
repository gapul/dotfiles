---
name: dotfiles-maintenance
description: Safely inspect, update, validate, commit, and rebuild this Nix-managed dotfiles repository. Use when changing files under ~/.dotfiles, adding packages or Flake inputs, updating nix-darwin or Home Manager configuration, or diagnosing a failed `just rebuild`.
---

# Dotfiles Maintenance

Work in `~/.dotfiles`. Preserve unrelated user changes and inspect `git status`
before editing.

## Workflow

1. Read the relevant Nix and application configuration.
2. Make scoped edits; keep cross-platform settings in `nix/home/common.nix`.
3. Run `git diff --check`.
4. For Nix changes, run:

   ```bash
   cd ~/.dotfiles/nix
   nix fmt
   nix eval --no-write-lock-file '.#homeConfigurations.gapul.activationPackage.drvPath' --raw
   ```

5. Run focused checks for edited Lua, JSON, shell, or TypeScript.
6. Commit only when explicitly requested.
7. Apply with `just rebuild` only when explicitly requested.

Do not run destructive Git commands. Do not overwrite generated application
state unless its source configuration and regeneration path are both clear.
