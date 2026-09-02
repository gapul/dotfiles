# Homelab operations

How the Proxmox-based self-hosting setup at home was built and run. The configuration itself
lives in `configs/homelab/<service>/`; the host layout is described here.

> **Superseded.** This setup was replaced by a single NixOS machine with no hypervisor. The
> configuration now lives in `nix/hosts/homeserver.nix` and `nix/homelab/`, and the steps taken
> that day are in [HOMESERVER_MIGRATION.md](HOMESERVER_MIGRATION.md). What follows is a record
> of what was replaced.

- LAN `192.168.116.0/24`, gateway `192.168.116.254`
- Hypervisor: Proxmox VE 9.1, `pve` at `192.168.116.100`
- tailnet `tail079f44.ts.net`, MagicDNS on

---

## 1. Containers and VMs

| ID | Name | LAN IP | tailnet | Role |
|----|------|--------|---------|------|
| pve | pve | `.100` | `100.101.225.43` | The Proxmox host |
| CT101 | dockge | `.65` | — | The Docker machine, managed through Dockge on :5001. Stacks live in `/opt/stacks/<name>/` |
| CT102 | tailscale-router | dhcp | `100.107.201.72` | Subnet router, advertising and approved for `192.168.116.0/24` |
| CT103 | caddy | `.119` | `100.64.125.107` | Reverse proxy: Caddy, listening on Tailscale only |
| CT104 | hermes | `.120` | — | The Discord agent backed by Claude |
| VM100 | haos | `.88` | — | Home Assistant OS |
| — | rpi4 | `.53` | `100.69.79.75` | Secondary server, primary AdGuard. Expected to be switched off during creative work |

---

## 2. How to reach things

| Purpose | Command or URL |
|------|----------------|
| Proxmox | `ssh root@192.168.116.100`, `https://pve.gapul.net` |
| Enter a container | From pve: `pct enter <id>` or `pct exec <id> -- <cmd>` |
| Raspberry Pi | `ssh pi@192.168.116.53` |
| Home Assistant over SSH | `ssh hassio@192.168.116.88`, through the add-on with an ed25519 key |
| Home Assistant web | `https://home.gapul.net` |
| Dockge | `https://dockge.gapul.net`, which is `.65:5001` |
| Git (Forgejo) | `https://git.gapul.net`, `.65:3003`. A self-hosted mirror of GitHub |
| AdGuard primary and secondary | `https://dns.gapul.net`, `https://dns2.gapul.net` |
| Monitoring | `https://status.gapul.net`, Uptime Kuma |

SSH authenticates with the ed25519 key in the Bitwarden agent
(`SHA256:2WG8EZOQ47X+XFzjXtuoytt8e3K8qsJd7r/FdbFKmM4`).

Containers such as `.65` and caddy cannot be reached over SSH from the Mac; go through pve with
`pct`. And `*.gapul.net` only resolves while Tailscale is connected, because Caddy listens on
the tailnet alone.

### Accounts

Passwords do not go in this repository, since it is in git. Real passwords live in Bitwarden;
what follows is the username and where to find the password.

| Service | Username | Authentication and where the password lives |
|----------|-----------|---------------------------|
| Proxmox over SSH | `root` | ed25519 key in the Bitwarden agent |
| Proxmox web, `pve.gapul.net` | `root@pam` | Password, in Bitwarden |
| Raspberry Pi rpi4 | `pi` | ed25519 key, written at imaging time, plus an emergency password in Bitwarden |
| Home Assistant web | `gapul` | Password, in Bitwarden |
| Home Assistant SSH add-on | `hassio` | ed25519 key, passwordless sudo |
| AdGuard primary and secondary | `gapul` | Password, in Bitwarden. `adguardhome-sync` uses the same credentials, and they exist only in the env of CT101's `/opt/stacks/adguardhome-sync/compose.yaml` |
| Dockge, `.65:5001` | to be confirmed | Password, in Bitwarden. If it is lost, run `docker exec -it dockge npm run reset-password` on CT101 |
| Uptime Kuma, `status.gapul.net` | created on first run | Password, in Bitwarden |
| Forgejo, `git.gapul.net` | `gapul` | Admin. Password and API token in Bitwarden |
| Cloudflare API, for Caddy's DNS-01 | — | The token is in CT103's `/etc/caddy/cf.env`, outside git |

Anything secret that does go into dotfiles is encrypted with SOPS through `.sops.yaml` and never
committed in the clear. `work/`, `conf/` and `.env` are already in `.gitignore`.

### SSH keys

The private keys are held by Bitwarden Desktop's SSH agent; no private key sits on the Mac as a
file, and `~/.ssh/*.bak` are backups. The agent offers two keys:

| Label | Type | Fingerprint | Use |
|--------|------|--------------------|------|
| `GitHub` | ed25519 | `SHA256:2WG8EZOQ47X+XFzjXtuoytt8e3K8qsJd7r/FdbFKmM4` | The homelab standard, registered everywhere below |
| `mvrx-dev` | RSA | `SHA256:4WQSmfgnETVJxL6I7R13l5b8Qu6mGpx65FTs7ELov0U` | Work, unused in the homelab |

The public key to register:

```
The public key is distributed from `ssh_authorized_keys` in `secrets/secrets.yaml` through SOPS.
```

Where it is registered:

| Host | User | How |
|--------|---------|---------|
| pve `.100` | `root` | Already in `~/.ssh/authorized_keys` |
| rpi4 `.53` | `pi` | Written by Raspberry Pi Imager at flash time |
| HA `.88` | `hassio` | `ssh.authorized_keys` in the add-on configuration |
| CT102 tailscale-router | `root` | Already present |

The key is not registered on CT101 (dockge), CT103 (caddy) or CT104 (hermes); reach those from
pve with `pct enter` or `pct exec`. To register it on a new host:

```bash
mkdir -p ~/.ssh && install -m 600 /path/to/decrypted/authorized_keys ~/.ssh/authorized_keys
```

Host keys, for known_hosts: the HA add-on at `.88` is
`SHA256:AxGmsu9vVDDMjp9+xKcZtIwTq7fePBlx3ruPUOgNzho`. Recreating the add-on can change it, in
which case `ssh-keygen -R 192.168.116.88`.

---

## 3. DNS: two AdGuards, distributed by Tailscale

Local DNS is made redundant with a primary on the Pi and a secondary on CT101, and ad blocking
is pushed to every device on the tailnet.

```
every tailnet device
   │ DNS, from Tailscale's global nameservers with Override on, in order:
   │   1. 100.69.79.75    primary, the Pi          ← normally
   │   2. 192.168.116.65  secondary, CT101         ← failover, reachable from outside through the CT102 subnet router
   │   3. Quad9 9.9.9.9                            ← only if both are down
   ▼
 AdGuard primary (.53) ──[adguardhome-sync, every 10 min]──▶ AdGuard secondary (.65)
   └ gapul.net alone goes through split DNS to Cloudflare (1.1.1.1) and on to Caddy's tailnet IP
```

- Primary: `configs/homelab/adguard/primary-pi/`, deployed to `~/adguard/primary-pi/` on the Pi.
- Secondary and sync: `/opt/stacks/adguard-secondary/` and `/opt/stacks/adguardhome-sync/` on
  CT101, managed by Dockge.
- The AdGuard admin user is `gapul`.
- The split DNS for `gapul.net` to Cloudflare is required. Remove it and `*.gapul.net` stops
  resolving on every other device, because public DNS rejects CGNAT addresses (100.64.x) as
  rebinding.
- Do not leave a LAN address in the global DNS list permanently. Putting `.65` there makes
  devices away from home time out and everything crawl, which is why reaching it through the
  subnet router is the right shape.
- Tailscale's DNS settings are at `https://login.tailscale.com/admin/dns`.

---

## 4. Stopping and restarting the Pi, for creative work

The Pi is expected to be switched off from time to time, for TouchDesigner and similar. The
secondary at `.65` keeps DNS running while it is off.

To stop it, always gracefully, to protect the SD card:

```bash
ssh pi@192.168.116.53 'sudo poweroff'
# once the green ACT LED goes out it is safe to pull the power; the red LED just means power is present
# pause the "AdGuard Primary Pi (.53)" monitor in Uptime Kuma to avoid a false alarm
```

To bring it back, plug it in — it boots on its own, and AdGuard comes back with
`restart:unless-stopped`. Confirm with `ssh pi@192.168.116.53 'docker ps'` and resume the
monitor.

While it is off, verified behaviour: the secondary at `.65` keeps resolving names and blocking
ads, and `gapul.net` survives through the Cloudflare split.

---

## 5. Reverse proxy: Caddy on CT103

Caddy runs natively under systemd on CT103. Its configuration is `/etc/caddy/Caddyfile`, from
`configs/homelab/caddy/Caddyfile` in dotfiles. It listens on Tailscale only, with ports 80 and
443 closed on the LAN, and gets its TLS through Cloudflare DNS-01, with `CF_API_TOKEN` in
`/etc/caddy/cf.env`.

To publish a new service:

1. Add a block to the Caddyfile on CT103:

   ```
   newsvc.gapul.net {
       tls { dns cloudflare {env.CF_API_TOKEN} }
       reverse_proxy 192.168.116.65:PORT
   }
   ```

2. Do not add the Cloudflare A record by hand. `just dns` compares Caddy's vhost list against
   what exists and lists what is missing; `just dns --apply` creates them, with proxied false,
   ttl 60, pointing at homeserver's tailnet address. The same command checks the public CNAMEs,
   the ones through the tunnel, against the ingress in `homelab/cloudflared.nix`.
3. `pct exec 103 -- systemctl reload caddy`

---

## 6. Monitoring: Uptime Kuma at status.gapul.net

Runs from `/opt/stacks/uptime-kuma/` on CT101, with its UI at `status.gapul.net`. The DNS
monitors check every minute that a name actually resolves.

- AdGuard secondary (.65) is supposed to be up permanently, so it alerts for real.
- AdGuard primary on the Pi (.53) gets switched off deliberately, so it is informational.
  Pause it before stopping the Pi.
- Home Assistant (.88) is an HTTP check.

No notification target is configured. Registering a Discord webhook would make the alerts
actually arrive, and fits the Discord integration that already exists.

---

## 7. Home Assistant, VM100 at .88

SSH in with `ssh hassio@192.168.116.88`, through the Advanced SSH & Web Terminal add-on, with
the ed25519 key authorised. The user is not root but has passwordless sudo.

The add-on refuses to start and loops if neither `ssh.password` nor `ssh.authorized_keys` is
set. If you are refused, check that the username is `hassio` rather than your Mac username. If
the host key changed, `ssh-keygen -R 192.168.116.88`.

Because it sits behind Caddy, `configuration.yaml` has:

```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 192.168.116.119   # Caddy on CT103
```

The `header_up -X-Forwarded-For` hack on the Caddy side has been removed, so real client
addresses are recorded.

Restart Home Assistant Core from Settings, System, through the power icon. Restarting through
Developer Tools has failed in a way that left the configuration unread.

---

## 8. Things that have caught us out

| Symptom | What to do |
|------|------|
| Docker Hub pull limits on the house's public IP | `docker pull --platform linux/amd64 mirror.gcr.io/<repo>:<tag>`, then `docker tag` back to the original name. No daemon restart needed |
| `exec format error` from reusing an image built for another architecture | arm64 on the Pi and amd64 on the containers do not mix. Pull the matching architecture |
| SSH to pve occasionally refused with `Permission denied` | The path flaps. Wait a few seconds and retry |
| zram doubled up and failed, on the Pi under trixie | Standardise on the OS's own `systemd-zram-generator` and drop zram-tools. Already reflected in `bootstrap.sh` |
| Ad blocking not working on this Mac | The Mac's Tailscale client is stuck on old DNS. Rebooting the Mac fixes it |

---

## 9. Git hosting: Forgejo at git.gapul.net

A git remote that is not GitHub, so the code is still at home if GitHub goes down or the
account is frozen.

A Docker stack on CT101 in `/opt/stacks/forgejo/`, from `configs/homelab/forgejo/` in dotfiles,
at `.65:3003` behind `git.gapul.net`. git is HTTPS only, with `DISABLE_SSH=true`, and push and
pull authenticate with a token. The admin is `gapul`, and the store is SQLite. `INSTALL_LOCK=true`
in the compose env skips the web installer, and the admin was created from the CLI with
`docker exec -u git forgejo forgejo admin user create --admin ...`.

It runs as a pull mirror: Forgejo pulls from GitHub every 15 minutes. Nothing about the Mac's
git usage changes — pushes still go to GitHub and get copied home. Because the pull is outbound,
the redundancy works even without Caddy, which is only there for the web UI, clone and push.

State:

- `dotfiles`, public, is registered as a pull mirror and working.
- `obsidian-vault`, private, needs a GitHub read token. Add it through Migration in the Forgejo
  UI, pasting the token.
- Publishing through Caddy: `git.gapul.net` to `.65:3003` is in the Caddyfile. It still needs
  the Cloudflare A record from section 5 and `pct exec 103 -- systemctl reload caddy`. The
  mirror works without this.

To add a mirror through the UI: plus, New Migration, GitHub, the repo URL, tick "This repository
will be a mirror", Migrate. Private repositories need a GitHub token.

---

## 10. Backups of the Proxmox guests

Two stages. vzdump packs every guest locally, and restic ships that offsite to Google Drive,
sharing the same restic repository as the Mac under a `host=pve` tag so deduplication works
across both.

```
02:00  vzdump, all guests, snapshot mode, zstd, keep-last=2, into /var/lib/vz/dump
03:00  restic backup /var/lib/vz/dump → rclone:google-drive:restic-backup, host=pve, tag=pve-vzdump
       restic forget --host pve --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
```

The vzdump job is in PVE's `/etc/pve/jobs.cfg`, visible through `pvesh get /cluster/backup`,
writing to `local` storage.

The restic layer is hand-built, since pve runs Debian and is outside nix:

- Script: `/usr/local/bin/restic-pve-offsite.sh`
- Timer: `/etc/systemd/system/restic-pve-offsite.{service,timer}`, daily at 03:00 with
  `Persistent=true`
- Secrets: `/root/.config/rclone/rclone.conf` for the Google Drive token and `/root/.restic.pw`
  for the restic password, both decrypted from SOPS and placed for pve's root alone, outside git

Run it by hand with `systemctl start restic-pve-offsite.service`. Check it with:

```bash
RCLONE_CONFIG=/root/.config/rclone/rclone.conf \
RESTIC_REPOSITORY=rclone:google-drive:restic-backup \
RESTIC_PASSWORD_FILE=/root/.restic.pw \
restic snapshots --host pve
```

To restore, `restic restore <ID> --target /tmp/r` and then bring it back through the PVE UI,
`pct restore` or `qmrestore`.

Notifications are not sorted: PVE's backup notification target is `mail-to-root`, which in
practice never arrives. Pointing it at Discord so failures are noticed is the next improvement.
The restic layer could equally move to the same ntfy path the Mac, mac mini and Pi use.

### The shared restic repository, 2026-07-20

The Mac, the mac mini and the Pi share the same repository,
`rclone:google-drive:restic-backup`, alongside pve, separated by host name and deduplicated
across all of them. What each host backs up, on what schedule, how it is deployed, where its
secrets live and how to test a restore are in
[`configs/homelab/restic/README.md`](../configs/homelab/restic/README.md), which also holds the
scripts, systemd units and launchd plists.

- Because the repository is shared, `restic forget` is always scoped with `--host`, and pruning
  happens only in the Mac's daily run, to avoid fighting over the exclusive lock. homeserver,
  which replaced pve, uses the same repository as `host=homeserver` from
  `nix/homelab/backup.nix` at 03:00.
- The Mac's restic-monitor looks at `monitoredHosts` in `nix/lib/restic-common.nix` per host.
  In a shared repository, looking at the single newest snapshot across the whole repository
  never warns as long as one machine is still writing, so a single dead host goes unnoticed.
  Add new hosts to `monitoredHosts` — forget and that host is unmonitored; leave a retired host
  in and it produces a false alarm every day.
- Snapshots from hosts that no longer write, meaning pve's vzdump and the cold and warm passes
  from the migration, are tagged `archive` and exempted from retention. Remove the tag and
  keep-monthly 6 will expire them.
- The Google OAuth client is published as Production, so the token does not expire. It used to
  be in Testing, where it expired roughly weekly and stopped every host at once. Failures
  notify through ntfy on the Mac, the mac mini and the Pi.
- To browse the contents from a phone, `files.gapul.net` is a read-only FUSE restic mount on
  pve with `--no-lock`, plus Filebrowser, published through Caddy on the tailnet without
  authentication. Cloudflare needs its own A record for `files.gapul.net` pointing at Caddy's
  tailnet address.
- Restore test, 2026-07-20: on the Mac, pve, the mac mini and the Pi, the SHA256 of the
  restored files matched the live ones.
- Homepage's Backup section lists Backrest, for browsing and restoring, and Filebrowser, for
  previewing contents.

### Home Assistant's own backups, still to do

The whole of VM100 is covered by vzdump above. Home Assistant's built-in automatic backup, for
restoring at the configuration level, is not set up and needs an encryption password chosen.

---

## 11. Proxmox improvements, 2026-06-29

Done:

- CT102 set to `onboot=1`, so the subnet router comes back after a reboot
- `swappiness=10` and fail2ban with the sshd jail enabled
- Keys only for SSH: `PasswordAuthentication no` and `PermitRootLogin prohibit-password` in
  `/etc/ssh/sshd_config.d/99-hardening.conf` on pve
- The backups in section 10, and CT101's rootfs brought from 96% to 51% by pruning unused
  images and `pct resize 101 rootfs +8G`
- 157 packages through `apt dist-upgrade`, which also removed the subscription nag

Still to do, each needing a decision, capacity or a secret:

1. **Reboot for the kernel.** `7.0.12-1-pve` is installed but `6.17.4` is running.
   `ssh root@192.168.116.100 reboot` picks it up, stopping every guest for a few minutes; DNS
   continues because the primary is on the Pi.
2. **The PVE firewall.** Enabling it remotely was ruled out: CT102 has `firewall=1` and would
   need adjusting, pve is itself a Tailscale node and needs UDP 41641 and friends allowed, and
   over the LAN there is no way to verify tailnet reachability, so a lockout would mean console
   recovery only. pve is not exposed publicly and has keys-only SSH plus fail2ban, which is
   adequate. If it is done, it should be done at the console.
3. **2FA for root@pam**, not configured. Register a TOTP through the web UI.
4. **Discord notifications for backups and failures.** Currently `mail-to-root`, which does not
   arrive. Register a Discord webhook as a PVE notification target.
5. **Slight memory overcommit**, 15872 MB allocated against 15360 MB physical. Reducing CT104
   from 4 G to 2 G and CT101 from 6 G to 4 G resolves it. Optional, not urgent.

---

## Related

- Per-service configuration: `configs/homelab/{adguard,caddy,forgejo,raspberrypi}/`
- Bootstrapping the Pi: `configs/homelab/raspberrypi/bootstrap.sh`
- General cheatsheet: `docs/CHEATSHEET.md`

---

## 12. Media servers: Jellyfin, Navidrome and Samba

Docker stacks on CT101, with the media on a dedicated volume carved out of Proxmox's
`local-lvm`.

### Storage

CT101's `mp0` is `local-lvm:vm-101-disk-1`, 200 G, mounted at `/mnt/jellyfin-media`, created
with `pct set 101 -mp0 local-lvm:200,mp=/mnt/jellyfin-media` and hot-pluggable while running.
Inside it are `movies`, `tv` and `music`. Resize with `pct resize 101 mp0 +NNG`.

### Services

| Service | URL | Port | Stack |
|---|---|---|---|
| Jellyfin, video | https://jellyfin.gapul.net | 8096 | `/opt/stacks/jellyfin/` |
| Navidrome, music | https://navidrome.gapul.net | 4533 | `/opt/stacks/navidrome/` |
| Samba, file sharing | `smb://192.168.116.65/media` | 445 | `/opt/stacks/samba/` |

Caddy on CT103 maps each `*.gapul.net` to `192.168.116.65:<port>`, with Cloudflare A records
pointing at `100.64.125.107`.

Samba's user is `gapul`, with the password in CT101's `/opt/stacks/samba/.smb-pass`, outside
git. From the Mac, Finder, Command-K, `smb://192.168.116.65/media`; from the tailnet it goes
through the CT102 subnet router.

### Hardware transcoding on the Intel iGPU, Alder Lake-N

`pct set 101 -dev0 /dev/dri/renderD128,gid=993 -dev1 /dev/dri/card1,gid=44`, hot-pluggable.
Jellyfin's compose gets `devices: [/dev/dri:/dev/dri]`, and in the UI, Dashboard, Playback,
Hardware acceleration, enable VAAPI on `/dev/dri/renderD128`.

### Dashboard and monitoring

Homepage's `services.yaml` has a Media group with Jellyfin and Navidrome. Adding HTTP monitors
for each URL in Uptime Kuma is worth doing.

### Note

To avoid the Docker Hub limits, Jellyfin comes from lscr.io and Navidrome and Samba from
mirror.gcr.io.
