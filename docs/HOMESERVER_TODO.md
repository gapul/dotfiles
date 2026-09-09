# What is left after the homeserver migration

The migration itself finished on 2026-08-11. Thirty containers and the native services are
running, memory went from 9.7 GB to 6.3 GB, and the tailnet address is `100.127.129.31`. The
steps taken that day, and what was learned doing it, are in
[HOMESERVER_MIGRATION.md](HOMESERVER_MIGRATION.md).

What stays here is the things that turned out to be broken only when someone tried to use them.
Pre-migration decisions and the day's runbook have served their purpose and are gone.

Rechecked against the running machine on 2026-08-16.

---

## Found and fixed on 2026-08-16

Kept as a record. Every one of these had the same shape: the service was up and the contents
were dead. gatus and podman both reported them healthy.

- **Home Assistant had been in recovery mode since it started on 8/11.** When
  `trusted_proxies` was corrected to `127.0.0.1` after the migration, it was written as
  `[127.0.0.1, ::1]`. In a YAML flow sequence `::1` cannot appear unquoted. For five days
  Matter, automations and MQTT were all dead while the container reported `Up` and passed its
  health check.
- **MQTT still pointed at the HAOS add-on**, connecting to `core-mosquitto` as user
  `homeassistant`. The `ha` user on the new mosquitto is new, so the password was regenerated
  and written into both `/var/lib/secrets/mosquitto-ha.password` and Home Assistant.
- **Matter was still set to `use_addon: true`**, pointing at
  `ws://core-matter-server:5580/ws`. With that setting Home Assistant calls into Supervisor's
  add-on management and the whole integration dies with `KeyError: 'hassio'`. That cascaded
  through `backup` and `cloud` until `default_config` failed to load at all. Changed to
  `ws://127.0.0.1:5580/ws`. The fabric in `/var/lib/matter-server` was intact, so nothing had
  to be paired again.
- **The tailnet subnet routes had gone unapproved for five days.** homeserver advertised three
  (`192.168.116.0/24`, `192.168.1.0/24`, `10.80.1.0/24`) and none were approved, while
  `tailscale-router` and `mvrx-relay` — both supposedly gone in the migration — still held
  primary. Deleting the dead nodes has to come before approving, or the traffic is pulled back
  to them anyway. Five machines that no longer physically exist (`caddy`, `pve`,
  `tailscale-router`, `mvrx-relay`, `mullvad-exit`) were removed, then the three routes were
  approved, and reaching the work development machine directly from the Mac was confirmed on
  both `192.168.1.36:22` and `10.80.1.36:22`. The ProxyJump detour is no longer needed.
- **homepage could not read services.yaml.** An empty group was left in it, which hit
  `null.forEach`, and the dashboard showed nothing but bookmarks. The contents had also gone
  stale in the migration — a deleted AdGuard, container names that had become native services,
  a glances pointing at the old CT101 address — so it was rewritten against the running
  machine.
- **samba had no `gapul` user.** The `sudo smbpasswd -a gapul` that should have been run on
  install day was missed, and `pdbedit -L` was empty. The `media` share lists anonymously,
  which makes it easy to assume that seeing it means it works. A password was created and
  registered, authentication was confirmed, a wrong password was confirmed to fail with
  `NT_STATUS_LOGON_FAILURE`, and the value went into Bitwarden.
- **Dawarich rejected its own tailnet address.** `APPLICATION_HOSTS` in `dawarich.env` was
  still `localhost,::1,127.0.0.1`, so a request to `100.127.129.31:3005` got a 403 from Rails
  host authorization. Nobody noticed because it had only ever been used from localhost. It
  would have bitten the moment OwnTracks on the phone started sending. The tailnet and LAN
  addresses were added, and an OwnTracks-shaped POST from the Mac was run through to confirm
  the point count went up.
- **fgc's ntfy notifications had never once arrived.** `NOTIFY` was
  `ntfy://fgc:<password>@127.0.0.1:8082/games`, and that `127.0.0.1` means the container
  itself. fgc is on the `podman` network and ntfy is on `ntfy_default`, so the name would not
  resolve either. The reason the plaintext password was visible in the logs — apprise prints
  the whole command on failure — is that it failed every single time. The destination is now
  `host.containers.internal:8082`, and authentication moved from a password to a write-only
  token for `games`, which is easier to revoke. One message from apprise was confirmed to
  arrive.

Home Assistant's `.storage` and `/var/lib/hass` are mutable state and are not in the
repository. If something breaks, `.storage/core.config_entries.bak-claude` and
`configuration.yaml.bak-recovery` sit in the same directory.

## Still open

- [ ] **Dawarich on the phone.** The server side is done: the login is
      `gapul@homeserver.local`, an API key exists, and `APPLICATION_HOSTS` is fixed. What
      remains is pointing OwnTracks on the iPhone at
      `http://100.127.129.31:3005/api/v1/owntracks/points?api_key=…`. Recording away from home
      requires Tailscale to stay on on the phone.
- [ ] **Bridge rooms still carry the old server_name.** Eighteen discord portals are
      `!…:matrix.gapul.net` and joining them returns 404. This is fallout from the July domain
      change, unrelated to the migration. Fixing it means recreating the portals, so it needs a
      decision. The telegram side reports `No user logins found` and has no login at all.
- [ ] **Leftovers from HAOS and the old host.** Waiting on a decision to delete.
      `core.entity_registry` still holds 63 entities with `platform: hassio`, permanently
      unavailable. `/var/lib/homelab` holds 17 MB of directories from retired stacks
      (backrest 785K, uptime-kuma 649K, adguard-secondary 16M, adguardhome-sync, wud,
      stirling-pdf.bak). The space is negligible; the only reason to delete is clarity.

## Worth doing once things settle

Not urgent, but each of these pays off.

- [ ] **Add a second NVMe and make it a ZFS mirror.** There is currently one disk and no
      redundancy (`rpool` 472 G, 5% used). `zpool attach` converts it without reinstalling.
      This matters more than a second node.
- [ ] **Move secrets into sops.** Once the host has an age key, the hand-placed files under
      `/var/lib/secrets` can go into `secrets/secrets.yaml`. restic's ntfy notification is
      waiting on this too.
- [ ] **Put the Raspberry Pi on NixOS too**, so the primary and secondary AdGuard can be
      generated from one definition.
- [ ] **Close gatus's blind spots.** No notification goes out when ntfy or the host itself is
      down. Watching homeserver from the Pi is the obvious answer. It also misses the shape
      seen above, where HTTP returns 200 but the contents are dead, which is worth thinking
      about.
- [ ] **A Mullvad exit node**, if it turns out to be wanted. CT106 was empty, so this is a
      fresh build. Give it its own netns rather than dirtying the host routing table.
- [ ] **deploy-rs or colmena**, once there are more hosts.
- [ ] **Turn containers into native services.** forgejo, navidrome and miniflux have modules.
      Only the ones where the data migration is worth it. The bridges' reasons for staying as
      they are are written at the top of `nix/homelab/matrix-bridges.nix`.
- [ ] **Move attic to `services.atticd`.** A postgres migration is involved, so do it on its
      own.
