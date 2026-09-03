# Offsite backups with restic, in a shared repository

The Mac, homeserver, the mac mini and rpi4 all share one encrypted restic repository,
`rclone:google-drive:restic-backup`, held on Google Drive through rclone. They are separated by
host name and deduplicated against each other.

| Host | What it backs up | Schedule | Implementation | Where the secrets live |
|---|---|---|---|---|
| The Mac, MacBook-Mini | Documents, Pictures, Downloads, Movies, Music, Minecraft | Daily at 13:00 | home-manager, `nix/home/restic-backup.nix`, through launchd | sops-nix |
| homeserver | `/var/lib`, the state of every service. The media in `/srv` and attic are excluded | Daily at 03:00 | NixOS, `services.restic.backups.homeserver` in `nix/homelab/backup.nix` | Placed by hand in `/var/lib/secrets/`, since there is no age key yet |
| The mac mini | `~/Developer` and `~/.config`, excluding node_modules, .venv, target, .git/objects and model weights | Daily at 05:00 | home-manager, `nix/home/macmini-backup.nix`, through launchd | Raw files placed by hand; sops is not set up there |
| rpi4 | `/home/pi`, the docker services' data | Daily at 04:30 | `restic-rpi-offsite.sh` and a systemd timer | `/root/.config/rclone/rclone.conf` and `/root/.restic.pw` |

The secrets are always the same two things — `rclone.conf`, holding the Google Drive token, and
the restic password — and neither is in this repository; they arrive through sops or by hand.

Because the repository is shared, `restic forget` is always scoped with `--host <this host>`,
and only the Mac's daily run prunes. Nothing else prunes, to avoid fighting over the exclusive
lock.

The Google OAuth client is published as Production, so the token does not expire. It used to be
in Testing, where it expired roughly weekly and stopped every host at once.

## Deploying

### rpi4, Debian on aarch64

```sh
sudo apt-get install -y restic rclone
# place the secrets: /root/.config/rclone/rclone.conf and /root/.restic.pw, from the Mac's sops
# and for notifications: /root/.config/ntfy/{url,token}
sudo install -m755 restic-rpi-offsite.sh /usr/local/bin/restic-rpi-offsite.sh
sudo install -m644 restic-rpi-offsite.service restic-rpi-offsite.timer /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now restic-rpi-offsite.timer
```

### The mac mini and homeserver, both declared

nix generates the script and the launchd or systemd unit, so there is no procedure here. Only
the secrets go in by hand, because neither machine has sops or age.

- The mac mini: `nix/home/macmini-backup.nix`. The secrets are
  `~/.config/rclone/rclone.conf` and `~/.config/restic/password`, plus
  `~/.config/ntfy/{url,token}` for notifications. `just rebuild` applies it.
- homeserver: `nix/homelab/backup.nix`. The secrets are
  `/var/lib/secrets/{rclone.conf,restic.password}`.

Until 2026-08-12 the mac mini used an imperative setup, `restic-macmini-offsite.sh` and
`local.restic-macmini.plist`. Both are gone, so do not put them back by reading this file.

## Browsing the contents from a phone, at files.gapul.net

An encrypted repository shows nothing useful on Google Drive. Previewing happens on homeserver,
through a read-only FUSE restic mount plus Filebrowser, declared in
`nix/homelab/restic-view.nix`. In the pve days these were hand-written systemd units; the
migration moved them into the declaration and the unit files here were deleted.

- The restic mount needs `--no-lock`, so a permanently mounted repository does not block the
  daily prune.
- Filebrowser listens on 8085. 8082 was the port in the pve days, and on homeserver the ntfy
  container has it — a collision created by folding everything onto one machine.
- Cloudflare needs its own A record for `files.gapul.net`; there is no wildcard.
- It is on the tailnet only, with no authentication.

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
