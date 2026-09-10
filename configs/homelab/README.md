# configs/homelab

> **Superseded (2026-08-09).** This setup was replaced by a single NixOS machine with no
> hypervisor. The configuration now lives in `nix/hosts/homeserver.nix` and `nix/homelab/`, and
> the steps taken that day are in
> [HOMESERVER_MIGRATION.md](../../docs/HOMESERVER_MIGRATION.md). What follows is a record of
> what was replaced.

The configuration for the self-hosting setup at home. How it was operated, how it was put
together and what went wrong are in [`docs/HOMELAB.md`](../../docs/HOMELAB.md).

## One directory per service

| Directory | Contents |
|------|------|
| `adguard/` | The two AdGuard Home instances — primary on the Pi, secondary on CT101, plus the sync — and the runbook |
| `caddy/` | The reverse proxy Caddyfile, on CT103, listening on Tailscale only |
| `raspberrypi/` | `bootstrap.sh` for the Pi: Docker, zram, log2ram, Tailscale, and the tweaks that keep the SD card alive |
| `forgejo/` | Self-hosted git, mirroring GitHub, at `git.gapul.net` |

## The hosts

pve `.100`, dockge on CT101 `.65`, caddy on CT103 `.119`, hermes on CT104 `.120`, Home
Assistant on VM100 `.88`, rpi4 `.53`.

Containers are reached from pve with `pct exec <id> -- ...`.
