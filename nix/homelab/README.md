# homelab stacks

The services that ran as Docker stacks on CT101, declared as podman containers.
Converted once with `compose2nix`; nothing regenerates them, because the compose
files they came from disappear with Proxmox.

## Secrets

No secret is in this tree. Where a compose file interpolated a value from its
`.env`, that entry was removed from `environment` and the container instead reads
`/var/lib/secrets/<stack>.env` at runtime.

This matters more than it looks. podman applies `-e` after `--env-file`, so an
entry left behind in `environment` — even an empty string, or an upstream default
like `password` — silently wins over the real value from the env file. The service
then starts with the wrong credential rather than failing.

Each file is root-owned, mode 0400, and written by hand at install time. Until
this host has an age key of its own, sops-nix cannot encrypt to it; move them into
`secrets/secrets.yaml` once it does.

Note that several keys are **not** named the way the old `.env` named them: the
compose files renamed them on the way into the container, and it is the container
name that matters now.

| file | keys |
| --- | --- |
| `archivebox.env` | `ADMIN_PASSWORD` |
| `attic.env` | `ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64`, `POSTGRES_PASSWORD` |
| `dawarich.env` | `POSTGRES_PASSWORD`, `DATABASE_PASSWORD`, `SECRET_KEY_BASE`, `OTP_ENCRYPTION_PRIMARY_KEY`, `OTP_ENCRYPTION_KEY_DERIVATION_SALT`, `OTP_ENCRYPTION_DETERMINISTIC_KEY`, `APPLICATION_HOSTS` |
| `matrix.env` | `CONDUIT_REGISTRATION_TOKEN` |
| `miniflux.env` | `DATABASE_URL` (the whole `postgres://miniflux:<pw>@db/miniflux?sslmode=disable` string), `POSTGRES_PASSWORD`, `ADMIN_PASSWORD` |
| `obsidian-couchdb.env` | `COUCHDB_USER`, `COUCHDB_PASSWORD` |
| `paperless.env` | `PAPERLESS_SECRET_KEY`, `PAPERLESS_ADMIN_PASSWORD` |
| `vaultwarden.env` | `ADMIN_TOKEN` |

`APPLICATION_HOSTS` is in dawarich's list not because it is secret but because the
old value names the old machine's LAN address; it has to be set for whatever this
host's address turns out to be.

Two of these passwords existed in plaintext in the compose files on the old host —
archivebox's admin password, and samba's, which was in `command:` and therefore
also visible in `ps`. They are worth rotating rather than carrying over.

## Data

Bind mounts moved with the machine:

- `/opt/stacks/<stack>/x` → `/var/lib/homelab/<stack>/x`
- `/mnt/jellyfin-media` (the old 200GB LVM volume) → `/srv`, its own ZFS dataset
  with auto-snapshot off
- the docker socket → podman's, on the host side only; containers still find it at
  `/var/run/docker.sock` because that is what homepage's and glances' configs say

Named volumes (`dawarich_*`, paperless's `data`/`media`, `redisdata`) are not bind
mounts and do not move by copying a directory: docker keeps them under
`/var/lib/docker/volumes` and podman under `/var/lib/containers/storage/volumes`.
Their contents have to be exported and imported.

## Health gating

Compose's `depends_on: condition: service_healthy` has no equivalent here.
compose2nix maps `depends_on` to systemd ordering, which starts the dependent
container once the other has *started*, not once it is *ready*. attic, dawarich,
miniflux and paperless all wait on a database that way, so expect the app
container to die once and be restarted by `Restart=always` on a cold boot.
