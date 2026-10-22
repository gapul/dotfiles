# Offsite backups with restic, in a shared repository

The Mac, homeserver, the mac mini and nixos-laptop all share one encrypted restic repository,
`rclone:google-drive:restic-backup`, held on Google Drive through rclone. They are separated by
host name and deduplicated against each other.

| Host | What it backs up | Schedule | Implementation | Where the secrets live |
|---|---|---|---|---|
| The Mac, MacBook-Mini | Documents, Pictures, Downloads, Movies, Music, Minecraft | Daily at 13:00 | home-manager, `nix/home/restic-backup.nix`, through launchd | sops-nix |
| homeserver | `/var/lib`, plus `/srv/dawarich` and `/srv/archivebox`. The media and attic are excluded | Daily at 03:00 | NixOS, `services.restic.backups.homeserver` in `nix/homelab/backup.nix` | sops-nix (`secrets/homelab.yaml`, opened with the SSH host key), installed in `/var/lib/secrets/` |
| The mac mini | `~/Developer`, `~/.config`, and the nightly Minecraft, Hermes and Presenta dumps under `/Users/Shared/*-backups` plus Presenta's media store, excluding node_modules, .venv, target, .git/objects and model weights | Daily at 05:00 | home-manager, `nix/home/macmini-backup.nix`, through launchd | sops-nix on the system side (`nix/hosts/macmini.nix`, opened with the SSH host key) |
| nixos-laptop | Documents, Pictures, Downloads, Music, Videos, `~/Developer`, `~/.config`, `~/.ssh`, keyrings | Daily at 13:00 | home-manager, `nix/home/restic-backup-linux.nix`, through systemd user timers | sops-nix |

The secrets are always the same two things — `rclone.conf`, holding the Google Drive token, and
the restic password — and neither is in this repository in plaintext; every host gets them through sops.

Pingvin Share X on homeserver is treated as a distribution cache. Its small SQLite database,
which holds the share information and the accounts, is backed up along with a consistency dump,
but the videos in `data/uploads` and the automatically generated ZIPs are not. The originals
stay on the project side, and after a failure the shares are recreated with `hs share create`.

Because the repository is shared, only the always-on mac mini runs the repository-wide
`restic forget --prune` and check, after its 05:00 backup. The Mac scopes its `restic forget` to
its own host without pruning, and homeserver does not forget at all, to avoid fighting over the
exclusive lock. `nix/home/restic-backup-linux.nix` (nixos-laptop) does not pass
`forgetOwnHostOnly`, so it still uses the shared default, `restic forget --prune`.

The Google OAuth client is published as Production, so the token does not expire. It used to be
in Testing, where it expired roughly weekly and stopped every host at once.

## Deploying

### The mac mini and homeserver, both declared

nix generates the script and the launchd or systemd unit, and sops-nix places the secrets with
each machine's SSH host key, so there is no procedure here.

- The mac mini: `nix/home/macmini-backup.nix`. `nix/hosts/macmini.nix` decrypts
  `~/.config/rclone/rclone.conf`, `~/.config/restic/password` and `~/.config/ntfy/{url,token}`
  for notifications. `just rebuild` applies it.
- homeserver: `nix/homelab/backup.nix`. `nix/homelab/secrets.nix` installs
  `/var/lib/secrets/{rclone.conf,restic.password}` from `secrets/homelab.yaml`.

Until 2026-08-12 the mac mini used an imperative setup, `restic-macmini-offsite.sh` and
`local.restic-macmini.plist`. Both are gone, so do not put them back by reading this file.

## Browsing the contents from a phone, at files.gapul.net

An encrypted repository shows nothing useful on Google Drive. Previewing happens on homeserver,
through Filestash, declared in `nix/homelab/{restic-view,filestash}.nix`. The same screen also
reaches Google Drive, while the backup side stays read-only.

- The restic mount needs `--no-lock`, so a permanently mounted repository does not block the
  daily prune.
- Filestash listens on 8099.
- Cloudflare needs its own A record for `files.gapul.net`; there is no wildcard.
- It is on the tailnet only, and goes through Caddy's shared authentication as well.

## Restore test, run on 2026-07-20, passed on every host

For each host, the SHA256 of the restored file matched the live one:

```sh
# on the target host, with that host's restic environment exported:
restic dump --host <host> latest <path> | sha256sum   # must match the live sha256sum
```

`restic ls` and `restic stats` over Google Drive tend to time out after two minutes and make
things look missing when they are not. To count files, use `restic find` for a specific path,
the `/mnt/restic-view` mount on homeserver, or the "processed N files" line in the backup run's
summary. Note that macOS has no `timeout`; it is `gtimeout`.
