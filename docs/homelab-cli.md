# Operating the homelab from code and the CLI

`hs` is the single entry point from the Mac. Web UIs may stay for browsing and for input meant
for humans, but starting, stopping, investigating and backing up do not treat the UI as the
source of truth.

```sh
hs list
hs status                          # everything
hs status paperless                # one container
hs logs paperless -f
hs restart paperless
hs exec paperless sh

hs unit status blocky
hs unit logs restic-backups-homeserver -n 100
hs unit restart syncthing

hs api romm GET /openapi.json
hs openapi bambuddy
hs share create exhibition-files never /path/to/vertical.mp4 /path/to/horizontal.mp4
hs ytdl check
hs backup snapshots
hs backup run
hs backup restore-drill
```

API keys go in `/var/lib/secrets/homelab-cli.env`, and never into git or the Nix store.

```sh
HS_BAMBUDDY_TOKEN=...
HS_MINIFLUX_TOKEN=...
HS_PAPERLESS_TOKEN=...
HS_ROMM_TOKEN=...
HS_HOMEASSISTANT_TOKEN=...

# For Pingvin Share X, which only offers cookie authentication.
# These are exchanged for a short-lived cookie at run time.
HS_PINGVIN_SHARE_EMAIL=...
HS_PINGVIN_SHARE_PASSWORD=...

# For any other cookie-based API handled directly.
HS_SOME_APP_COOKIE='session=...'
```

## How each thing is reached

| Kind | Services | Route from code or the CLI |
|---|---|---|
| Standard REST or OpenAPI | Bambuddy, Dawarich, Home Assistant, Jellyfin, Miniflux, Paperless, Readeck, RomM, Syncthing | `hs api`, and each service's OpenAPI or REST API |
| Standard protocols | Anki, Attic, CouchDB, Forgejo, Matrix, Navidrome, ntfy, Radicale, Samba, Vaultwarden | Each one's official CLI, or HTTP, CalDAV or SMB |
| A CLI inside the app | ArchiveBox, Forgejo, Navidrome, Paperless, Pingvin Share X, ytdl-sub | `hs archivebox`, `hs forgejo`, `hs navidrome`, `hs paperless`, `hs share`, `hs ytdl` |
| The file is the source of truth | Fava and Beancount, Homepage, SearXNG, Blocky, Authelia, cloudflared, Filestash, Pingvin Share X | Configuration in git plus `hs unit`. Only Filestash's private key lives in `/var/lib/secrets` |
| Internal HTTP APIs | Calnode, Gameyfin, Hauk, Pingvin Share X, Spliit | `hs api` or `hs exec`. A daily contract check catches the entry point breaking |
| Host operations | Every podman container, every systemd service, restic | `hs status/logs/restart/exec/unit/backup` |

Rallly's self-hosted version publishes an OpenAPI document while upstream restricts issuing API
keys as a licensing matter. Modifying it to get around that restriction is not on the table. For
now its configuration, database and lifecycle are managed from the CLI, and creating and editing
polls stays in the web UI. A replacement gets installed alongside, and switched to after
migrating the data, once a candidate satisfies all of:

- It is actively maintained, with a rolling tag or continuous container releases.
- It can keep guest voting.
- It has a public API for creating, updating, fetching and deleting polls.
- The existing Rallly data can be migrated or kept in parallel without losing anything.

Crab Fit has a public API but was last updated in 2023, which makes it less maintainable than
the current Rallly, so it is not a replacement. Nor is going back to abandoned software just
because its GUI is newer.

## What is being replaced

- Pinchflat is replaced by `ytdl-sub`, whose subscriptions can be managed in YAML.
- File Browser's role moves to Filestash, which can show Google Drive and the read-only restic
  mount at the same time. The data on Drive itself does not move.
- The old Pingvin Share is replaced by Pingvin Share X, which is released on a rolling tag.
- As a rule, no new software gets added whose main operations can only be reproduced through a
  web UI.

`api-contract-check.timer` verifies daily that the APIs are still reachable and notifies ntfy
about breaking upstream changes. Persistent databases get a consistent dump before the daily
backup, and `restore-drill.timer` genuinely restores one into a separate database every month.
