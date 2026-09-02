# Homelab roadmap and service migration notes

> **Superseded (2026-08-09).** This setup was replaced by a single NixOS machine with no
> hypervisor. The configuration now lives in `nix/hosts/homeserver.nix` and `nix/homelab/`, and
> the steps taken that day are in [HOMESERVER_MIGRATION.md](HOMESERVER_MIGRATION.md). What
> follows is a record of what was replaced. Where a question has since been answered, the
> answer is noted inline.

Last updated 2026-07-05.

Remaining work and migration research for a home lab built around pve (Proxmox) and CT101
(dockge on Docker). Task numbers match the Claude Code task list.

---

## 0. Background, done on 2026-07-05

- **Matrix published on the apex domain.** server_name was rebuilt from `matrix.gapul.net` to
  `gapul.net` and Conduit had federation enabled. The existing "homelab-pi" Cloudflare Tunnel
  was reused to publish `matrix.gapul.net`, with Caddy serving the well-known delegation for
  `gapul.net`. federationtester passed. The account `@gapul:gapul.net` was created and
  registration locked. This was the first ingress from the internet into the house.
- **dash.gapul.net (homepage) was filled out** with docker statistics, a Proxmox widget on a
  read-only token, siteMonitor, Glances for host CPU, RAM and temperature, weather and theming.
  The display language was switched to English.

---

## 1. Remaining work

### A. Matrix bridges

- **#7, logging discord and telegram in.** The appservice side is done: the domain was
  corrected, they are registered with Conduit, and they reconnect. What is left is a user
  action — DM `@telegrambot:gapul.net` with `login`, and DM `@discordbot:gapul.net` with
  either `delete-all-portals` to regenerate the old portals or `login-qr`.
- **#8, building signal, slack, twitter and meta.** These were never set up and sat in a crash
  loop with `homeserver.address not configured`. Generate a bridgev2 config, point it at
  gapul.net, `register-appservice`, then log into each network. One at a time.
- **#9, adding a Google Messages bridge.** Add `mautrix-gmessages` to the compose file,
  configure and register it, then DM `@gmessagesbot` and pair by QR from Google Messages on the
  phone. #8 and #9 are the same procedure, so doing them together is more efficient.

### B. Operational hardening

- **#10, pinning `latest` images.** Every stack ran `:latest`. Following latest was part of why
  the bridges broke that day. Digests were collected for the Matrix stack:
  - conduit `sha256:4078e80577ccaaf05290a7bb08badc321a5c44a8c8f5f3dce0fb1ae5a0825e64`
  - mautrix/discord `sha256:7716389dfb11dc7a44c8363348a48e91c1c463ded012f0fb08cdf266fcb20246`
  - mautrix/telegram `sha256:17b71cf6d45d7fb4eff3e9ea254613881df6531989031efbfccad12acc1d0782`
- **#11, testing the restore.** Verify that vzdump plus restic to Google Drive can actually be
  restored: `restic check`, snapshot listing, a trial restore, coverage of Vaultwarden and the
  new Matrix data, and retention.
- **#12, moving plaintext secrets into env or sops.** The Proxmox token in homepage's
  services.yaml, Conduit's registration token in the compose file, and `CF_API_TOKEN` in cf.env
  were all in the clear. At minimum a `.env` with permissions; ideally sops or docker secrets.
- **#13, deleting Conduit's registration token.** `ALLOW_REGISTRATION=false` was already set,
  but the token remained in the compose file, inert. Clean it up.
- **#14, splitting the Cloudflare token so it is DNS-only.** Caddy's token could edit both DNS
  and tunnels, which is more than it needs. Caddy's should be `Zone:DNS:Edit` alone. Creating
  the token is a dashboard action.
- **#15, hardening the public Matrix.** Rate limiting and WAF for `matrix.gapul.net`, and
  keeping Conduit updated. Rules are likely outside what the token can do, so this is dashboard
  work.
- **#16, tidying up.** `cw-data.old-matrixdomain`, `db.old`, `synapse.old` and backup tarballs
  under `/opt/stacks/matrix`, and homepage's `services.yaml.bak-*`. Consider putting a socket
  proxy in front of the docker.sock that homepage and glances use.

Ordering: decide #17, leaving Conduit, before doing #10 (pinning conduit) and #13 (removing the
token). #14 and #15 both require dashboard work.

---

## 2. Migration research, 2026

### 2.1 Clearly worth doing

#### Leaving Conduit: Tuwunel (keeps data) or continuwuity (wipes) — #17

Conduit's development had stalled while it was federating publicly. Maintenance is security, so
leaving it was the recommendation. The choice of destination mattered:

- Plain Conduit's RocksDB is **not compatible with continuwuity**. Going there wipes the data.
  conduwuit's Conduit compatibility was one-way, then broke, then was removed; continuwuity
  inherits that.
- **Tuwunel** migrates a Conduit RocksDB in place as of 1.8.0, keeping rooms, media and knocks.
  Technically the right answer if the data matters. It is effectively a one-person project with
  corporate and Swiss-government ties, and some inter-project drama.
- **continuwuity** is the non-corporate community successor and is actively maintained (0.5.x).
  It cannot keep the data, but keeping server_name as `gapul.net` restores federation, so for a
  small personal server a wipe is tolerable.
- Both are `CONDUIT_*` environment compatible. Appservices register through
  `register-appservice` in the admin room, so bridges must be re-registered.
- Always back up the data directory and test on a copy first. A continuwuity or tuwunel
  database cannot go back to Conduit.
- Effort low to medium.
- Synapse and Dendrite both require a wipe as well, and were judged excessive at this scale.

> **Outcome (2026-08-31).** Neither was chosen. The server moved to Synapse, because bridges
> were about to go from two to roughly ten and Conduit keeps appservice registrations inside
> RocksDB where only the admin room can reach them. Synapse reads them from config files, which
> makes the whole bridge fleet declarable. See `nix/homelab/matrix.nix`.

#### Uptime Kuma to Gatus — #18

A single Go binary, YAML declarations, roughly a third of the memory (10-40 MB against Kuma's
100 MB and up). It fits config-as-code directly.

HTTP, TCP, ICMP, DNS, TLS and push checks; conditions on status, latency, JSONPath over the
body and certificate expiry; status pages, maintenance windows, badges and an API. ntfy is
supported natively, so the existing notification path carries over. sqlite is the recommended
store.

There is no importer; about twenty checks have to be redeclared in YAML, a few hours' work.
History resets.

Complementary rather than competing: **Beszel** for agent-based resource monitoring, and
**Healthchecks** for whether cron jobs and backups are alive.

Effort low. Run Kuma alongside for a week, confirm parity, then remove it.

#### WUD to Diun — #19

Go, notification only, no web UI, light (20-40 MB, sleeping between cron runs). ntfy is
supported natively. `watchByDefault=true` watches all twenty-five containers at once, or the
`diun.enable=true` label selects them individually.

It fits "notify, never update automatically", which pairs with pinning (#10). Watchtower is a
different thing, since it updates.

If WUD's web UI, REST API, Home Assistant and MQTT integrations are unused, it is dead weight.

Effort low, twenty to thirty minutes.

#### Obsidian: CouchDB to Syncthing — #20

Syncthing is already running, so this removes one whole service (CouchDB, 150-300 MB, needing
backup and updates).

It comes with conditions. Syncthing works at file level, so editing the same note on two
devices at once produces `.sync-conflict` files. `.obsidian/workspace*.json` differs per device
and needs a `.stignore`, and Syncthing does not sync `.stignore` itself.

Mobile is the weak point. There is no official iOS app; the options are Möbius Sync (paid) or
SyncTrain (free, needs sandbox integration), both fighting iOS background limits. Android is
fine.

The judgement: desktop-centred, one device at a time, mobile mostly Android or read-only, then
migrate. Frequent simultaneous editing on iOS, then stay on LiveSync, which is realtime, merges
per chunk, and has a proper mobile client. Obsidian's own paid Sync is an option if
zero-maintenance matters more.

Effort thirty to sixty minutes on desktop, plus per-device work on mobile, iOS being the long
one. Sync is not backup — back up first.

### 2.2 Depends — #21

- **RSSHub to rss-bridge.** PHP, no Redis, no Chromium, so much lighter. But RSSHub has over a
  thousand routes against rss-bridge's roughly two hundred plus a generic CssSelectorBridge. A
  handful of common sites, use rss-bridge; many niche ones, stay. Miniflux consumes either.
  Migration means recreating feed URLs.
- **ArchiveBox to linkding.** These are not equivalent. linkding is lightweight bookmark
  management with optional light archiving, mainly through the SingleFile extension. ArchiveBox
  is a real archiver that drives Chromium to save HTML, PDF, screenshots, WARC and video. If
  what is actually happening is "links to read later", linkding is orders of magnitude lighter.
  If the point is defending against link rot, stay. URLs migrate through Netscape bookmark HTML
  but archived content does not; keep the old data as a static store.

### 2.3 Hobby-tier, no need to change

- **AdGuard Home to Blocky.** Go, one YAML file, no UI, about half the memory. Appealing if you
  like config-as-code, but it gives up AGH's UI, query log, per-client control and DHCP. The
  pair is already redundant, so this is low priority.
- **Homepage to Glance.** Go, YAML, a light "morning briefing". A different purpose from
  homepage's deep per-service widgets, which had just been built out. Plenty of people run
  both.

### 2.4 Other candidates found while going through the rest

- **#22, Proxmox VE to Incus.** Medium to high effort, the largest piece of work here, and the
  one migration that genuinely fits config-as-code. Incus (from LXD) is light, fully open
  source and API- and CLI-first, and pairs well with a declarative NixOS host. The constraints
  are Linux guests only, so no Windows VM, a weak UI and a small community. vzdump plus
  qemu-img can migrate. Safest to run it alongside Proxmox and start with new Linux workloads.
- **Add NFS next to Samba**, not instead of it. Linux-to-Linux shares are lighter and faster
  over NFS. Samba stays as the cross-OS default. Low effort.
- **dockge to Komodo**, conditionally medium. Worth it once there is more than one Docker host,
  for git-driven fleet management. Overkill for a single host.

### 2.5 Leave alone, already light or already the best

Vaultwarden (Rust, around 50 MB, far lighter than official Bitwarden), Miniflux (Go; FreshRSS
would be sideways), ntfy (HTTP-first, UnifiedPush), Navidrome (gonic is lighter but loses the
UI, and 50 MB is noise), Jellyfin (the winner among open-source video), Forgejo (already the
GPL community fork, Gitea-compatible), Paperless-ngx (every alternative is worse at OCR; the
weight is what being the category leader costs), dockge (ideal on a single host), Caddy (best
fit for config-as-code, automatic TLS), Home Assistant (2000-plus integrations, no
replacement), Radicale (the lightest; if a client struggles, Baïkal or Davis), Samba (the
cross-OS default).

Supporting databases (Redis, Postgres) stay separate per stack. Sharing them creates a single
point of failure, couples upgrades and complicates backups, and saves a few megabytes.

---

## 3. Suggested order

1. Groundwork with immediate effect: #11 restore testing, then, once #17 is decided, #10
   pinning and #13 token removal.
2. Lighter and sturdier: #17 leaving Conduit, #20 moving Obsidian to Syncthing (one service
   fewer), #18 Gatus, #19 Diun.
3. Bridges: #7 logins, then #8 and #9 built together as bridgev2.
4. Dashboard work: #14 splitting the token, #15 WAF and rate limiting.
5. Long term: #22 Proxmox to Incus, after running it alongside.

Every migration goes: back up the data directory, test on a copy, then do it for real.
Especially Matrix and Vaultwarden.
