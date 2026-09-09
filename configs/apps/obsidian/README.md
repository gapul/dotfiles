# Obsidian configuration snapshot, a tracking mirror only

This directory is a one-way snapshot of Obsidian's `.obsidian` configuration.

The real thing lives in the vault, at `~/Documents/notes/.obsidian`. What is here is a
read-only mirror, for history and diffs.

It is updated with `just obsidian-snapshot`, which goes from the vault into dotfiles and never
the other way. Copying back would create two owners and break the sync.

Day-to-day syncing is Obsidian Git and Self-hosted LiveSync's job. dotfiles does not own the
contents.

## Designed for a public repository

This repository is public, so:

- Only files confirmed to be safe are included, by whitelist: `app`, `appearance`, `hotkeys`,
  `community-plugins`, `core-plugins`, `graph`, `daily-notes`, `types` and `canvas`.
- Some things are never included: `plugins/*/data.json`, which can hold LiveSync's CouchDB
  credentials and various API keys; `workspace*.json`, which is per-device state;
  `copilot-index-*` and `.smart-env`, which are caches; and the plugins themselves.
- `just obsidian-snapshot` aborts if it finds a non-empty secret value, and `gitleaks` runs
  before the commit as well.
- Configuration that has to be versioned along with its secrets is encrypted with sops first,
  through `just secrets` and `.sops.yaml`.
