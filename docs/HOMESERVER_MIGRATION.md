# Migrating homeserver from Proxmox to NixOS

The day's runbook for replacing pve, a single Proxmox node, with one NixOS machine and no
hypervisor. The configuration side was already finished in `nix/hosts/homeserver.nix` and
`nix/homelab/`, with the CI VM test confirming it boots. What was left was moving the data,
placing the secrets by hand, and the one-time authentications.

This is not a staged migration, so there is no per-service rollback. The moment pve is gone,
there is nothing to go back to.

Decisions and manual steps still outstanding are in [HOMESERVER_TODO.md](HOMESERVER_TODO.md).
This page is the runbook alone.

---

## 0. What to understand before anything disappears

The current vzdump backups are in `/var/lib/vz/dump`, which sits on the same NVMe that is about
to be replaced, so formatting takes them with it. Until a copy exists outside the box, the
backup is not functioning as a backup.

If a rollback becomes necessary, the only route is reinstalling pve and restoring from whatever
was copied out. That takes hours.

The house keeps its internet throughout. The primary DNS is on the Raspberry Pi, not on this
machine.

---

## 1. The day before

### 1.1 A final Home Assistant backup

```sh
ssh -J root@100.101.225.43 root@192.168.116.88   # or from pve's console if that does not work
ha backups new
```

The container version has no built-in backup, so this is the last full backup Supervisor will
ever make.

### 1.2 Rotating the plaintext passwords

Two passwords were in the compose files in the clear, and samba's is in `command:`, which means
it shows up in `ps` as well. The migration is a good moment to change them:

- ArchiveBox's admin password
- The samba share user `gapul`'s password

The new values go into `/var/lib/secrets/archivebox.env` and `smbpasswd` after the migration.

### 1.3 Cloudflare A records

Two kinds of change: two records to add, and more than twenty to repoint.

The additions are `esphome.gapul.net` and `nodered.gapul.net`. Both were previously reached
through Home Assistant add-on ingress, and with Supervisor gone that entrance disappears, so
they become independent vhosts. Same shape as the existing ones: type A, proxied false, ttl 60.

The repointing is the bigger half, and it can only be done after the migration. Every
`*.gapul.net` currently points at Caddy's tailnet address, `100.64.125.107` on CT103, and moving
Caddy to the new host changes that address. Editing twenty-odd records by hand guarantees
missing one and finding out later that a single service does not connect, so there is a script.

```sh
export CF_API_TOKEN=...   # Zone:DNS:Edit
scripts/cf-repoint-records.sh --from 100.64.125.107 --to <the new host's tailnet IP>
# check the listing, then
scripts/cf-repoint-records.sh --from 100.64.125.107 --to <the new host's tailnet IP> --apply
```

It is a dry run by default. `tailscale ip -4` gives the new host's address. The certificate is a
wildcard, but the DNS records are not, so each one is needed individually.

### 1.4 Checking restic still works

The rclone Google Drive token expires after about a week of disuse, and both hosts then stop
silently. Finding that out on the day means having nowhere to put the data.

```sh
restic -r rclone:google-drive:restic-backup snapshots | tail -5
```

---

## 2. Getting the data out, 35 GB

It goes either to the restic repository on Google Drive or to the Mac. The 200 GB mount is on
the same NVMe, so it is not a destination.

### 2.0 Stop the services first

Copying a running postgres, couchdb or SQLite data directory captures a half-written state that
turns out to be corrupt when restored. This is the quietest way for a migration to fail.

```sh
ssh pve 'pct exec 101 -- sh -c "cd /opt/stacks && for d in */; do (cd \$d && docker compose down); done"'
ssh pve 'qm shutdown 100'    # HAOS
```

If stopping is not an option, at least take logical dumps of the databases: `pg_dump`, and
replication for CouchDB. But when stopping is possible it is both safer and faster.

From this point the house's services are down. The internet keeps working, since primary DNS is
on the Pi.

### 2.0.1 Grab the irreplaceable things first, which can happen before stopping

Small things that cannot be reconstructed if lost. Worth taking separately from the slow main
copy. These were taken on 2026-08-09, into `~/tmp/homeserver-migration/` on the Mac:

| File | Contents |
|---|---|
| `haos-backup-dc879ac6.tar`, 28 MB | The HAOS full backup: HA config, the Matter fabric, the Node-RED flows |
| `syncthing-identity.tar`, 20 KB | Syncthing's cert.pem, key.pem and config.xml |
| `CHECKSUMS.txt` | sha256 of both |

Their contents can change before migration day — HA's database keeps running — so take them
again on the day. Taking them early is still worth it, because for the fabric and Syncthing's
identity, damaged or stale beats absent by a wide margin.

### 2.1 Bind mounts and host directories

```sh
ssh pve 'pct exec 101 -- tar -C /opt -czf - stacks' > ~/migration/ct101-stacks.tar.gz
ssh pve 'pct exec 101 -- tar -C /mnt -czf - jellyfin-media' > ~/migration/bulk.tar.gz
```

### 2.2 Named volumes, which copying does not move

docker keeps them in `/var/lib/docker/volumes` and podman in
`/var/lib/containers/storage/volumes`. Rather than carrying the directory across, export and
import them. The names match on both sides.

```sh
for v in dawarich_dawarich_db_data dawarich_dawarich_public dawarich_dawarich_shared \
         dawarich_dawarich_storage dawarich_dawarich_watched \
         paperless_data paperless_media paperless_redisdata; do
  ssh pve "pct exec 101 -- docker run --rm -v $v:/v alpine tar -C /v -cf - ." > ~/migration/$v.tar
done
```

### 2.3 All of Home Assistant, in one full backup

Rather than pulling directories out of HAOS individually, one Supervisor full backup is faster
and contains everything, config and add-on data alike.

Create it from the serial console. The SSH add-on runs with protection mode on, so running `ha`
from inside it is refused with `unauthorized: missing or invalid API token`. The SSH add-on can
see `/backup` though, so create over serial and fetch over SSH.

```sh
# create, from pve into HAOS's serial console. Login is root with no password.
ssh pve
{ printf "\n"; sleep 3; printf "root\n"; sleep 6; \
  printf "nohup ha backups new --name pre-nixos-migration > /tmp/bk.log 2>&1 &\n"; sleep 5; \
  printf "exit\n"; sleep 2; } | timeout 35 socat - UNIX-CONNECT:/var/run/qemu-server/100.serial0

# fetch, from the Mac
ssh hassio@192.168.116.88 'ls -lh /backup/'
ssh hassio@192.168.116.88 'cat /backup/<slug>.tar' > ~/tmp/homeserver-migration/haos-backup.tar
```

What is inside and where it goes:

| tar inside the backup | Contents | Restore to |
|---|---|---|
| `data/` in `homeassistant.tar.gz` | The whole config: `configuration.yaml`, `.storage`, `custom_components` (HACS), `home-assistant_v2.db`, `esphome/` | `/var/lib/hass` |
| `data/` in `core_matter_server.tar.gz` | The Matter fabric, in `certificates/` | `/var/lib/matter-server` |
| `config/` in `a0d7b954_nodered.tar.gz` | The Node-RED flows | `/var/lib/node-red` |
| `core_mosquitto.tar.gz` | mosquitto's persistent data | `/var/lib/mosquitto` |
| `5c53de3b_esphome.tar.gz` | `addon.json` and nothing else | Not needed |

The ESPHome yaml is not add-on data; it is on the HA config side, in `data/esphome/`. Searching
the add-on's tar finds nothing, which is confusing.

Losing the Matter fabric means factory-resetting and re-pairing every Matter device. After
extracting, always confirm with `tar -tzf` that `data/certificates/` is in there.

### 2.3.1 VM105's disk image, as insurance

The company L2TP tunnel is declared in `nix/homelab/vpn-relay.nix`, but CI cannot verify it —
the sandbox cannot reach the company endpoint. If the native version does not come up first
time, work stops, so keep the whole old VM disk.

```sh
ssh pve 'qm stop 105; dd if=/dev/pve/vm-105-disk-0 bs=4M status=progress | zstd -T0' > ~/migration/vm105.img.zst
```

Only a little of the 10 GB is actually used, so it compresses well. Feeding it to `libvirt` on
the new host brings the old relay back in minutes. Once the tunnel has come up even once in the
new environment, it can be thrown away.

### 2.4 Syncthing's identity

cert.pem and key.pem in `/opt/stacks/syncthing/config/config/`. They are the device ID;
regenerating them makes the Mac see a different machine and rescan every folder.

### 2.5 Verify what was copied out

A backup that cannot be restored is not worth taking, so extract one tar as a test and look
inside it.

---

## 3. Installing

### 3.1 The ISO

Use this repository's recovery ISO. The Mac is aarch64-darwin and cannot build it locally, but
CI's Recovery ISO job builds one every time and uploads it as an artifact.

```sh
gh run download --name "nixos-recovery-<sha>" --dir ~/tmp/iso
# check the SHA256 against the bundled checksum before writing it
```

Use the ISO from the same commit as the generation being installed. A zpool enables feature
flags from the ZFS that created it, so an ISO that is too new can leave the installed system
unable to import the pool. The same commit means the same nixpkgs, so they agree.

The ISO contains:

- ZFS, `zpool` and `zfs`. Without them disko cannot create the pool.
- disko, git, neovim, sops, age, cryptsetup.
- flakes, already enabled. Without that, both `disko --flake` and `nixos-install --flake` stop
  on the very first command with "experimental Nix feature 'nix-command' is disabled".
- Our own cachix registered as a substituter. CI pushes the host's closure, so installing is a
  download rather than a build.
- This runbook. `homeserver-guide` opens it, readable before Tailscale authentication and
  therefore without a network.

### 3.2 Partitioning

Nothing after this is reversible. Before running it, confirm once more that everything from
section 2 is outside the box.

```sh
sudo disko --mode destroy,format,mount --flake github:gapul/dotfiles?dir=nix#homeserver
```

This lays down a fresh GPT with a 1 GB ESP and gives the rest to a zpool called `rpool`. The
datasets are root, nix, var-lib, srv and home; only srv is excluded from snapshots.

### 3.3 Installing

```sh
sudo nixos-install --flake github:gapul/dotfiles?dir=nix#homeserver
sudo nixos-enter --root /mnt -c 'passwd gapul'

# place the key, the only way in after the reboot. /home is its own dataset,
# so confirm it is mounted with findmnt before writing to it.
findmnt /mnt/home
sudo install -d -m 700 -o 1000 -g 100 /mnt/home/gapul/.ssh
curl -sL https://github.com/gapul.keys | sudo tee /mnt/home/gapul/.ssh/authorized_keys
sudo chown 1000:100 /mnt/home/gapul/.ssh/authorized_keys
sudo chmod 600 /mnt/home/gapul/.ssh/authorized_keys

# Required: hand the pool back before rebooting.
#   Skip this and the pool keeps the installer's hostId, and the new system,
#   with forceImportRoot=false, refuses to import it and will not boot.
sudo umount -R /mnt
sudo zpool export rpool
reboot
```

If `zpool export` was forgotten, the boot drops into the initrd emergency shell.
`emergencyAccess = true` is set, so it lets you in without a password:

```sh
zpool import -f rpool
zpool export rpool
reboot
```

---

## 4. Secrets and one-time authentication

Everything is root-owned and 0400. sops-nix is unusable until this host has an age key, so the
first placement is by hand; once the key exists they move into `secrets/secrets.yaml`.

| Path | Contents |
|---|---|
| `/var/lib/secrets/acme-cloudflare.env` | `CF_DNS_API_TOKEN=...`, the same token as the old `/etc/caddy/cf.env`, but under a different variable name |
| `/var/lib/secrets/restic.password` | The restic repository password |
| `/var/lib/secrets/rclone.conf` | The rclone configuration, with the google-drive remote |
| `/var/lib/secrets/mosquitto-ha.password` | Just the hash part, in mosquitto_passwd format |
| `/var/lib/secrets/gatus.env` | `NTFY_TOPIC` and `NTFY_TOKEN`. gatus does not start without them |
| `/var/lib/secrets/<stack>.env`, eight of them | The keys are listed in `nix/homelab/README.md` |
| `/var/lib/secrets/mvrx/`, six files | The company tunnel, also in `nix/homelab/README.md` |

Some of the `<stack>.env` key names differ from the old `.env` files. paperless's
`PAPERLESS_SECRET` is `PAPERLESS_SECRET_KEY` inside the container, and miniflux needs the whole
`DATABASE_URL` rather than the password alone. Getting these wrong does not make the service
fail; it starts with the wrong credentials.

The mosquitto hash:

```sh
mosquitto_passwd -c /tmp/p ha       # prompts for the password
cut -d: -f2 /tmp/p > /var/lib/secrets/mosquitto-ha.password
```

One-time authentication:

```sh
sudo tailscale up --advertise-routes=192.168.116.0/24,192.168.1.0/24   # approve the routes in the admin console
tailscale ip -4     # this is the address the DNS repointing in 1.3 uses
sudo smbpasswd -a gapul
# AdGuard's admin account is created on the first-run screen at https://dns2.gapul.net
```

---

## 5. Restoring the data

Watch the ownership. Everything in the old setup ran as root in docker containers; the native
services each run as their own user.

| Destination | Owner |
|---|---|
| `/var/lib/homelab/<stack>/` | root, since the containers run as root |
| `/srv/`, formerly /mnt/jellyfin-media | root |
| `/var/lib/hass`, `/var/lib/matter-server` | root |
| `/var/lib/syncthing/.config/syncthing/`, cert.pem and key.pem | `syncthing` |
| `/var/lib/esphome` | `esphome` |
| `/var/lib/node-red` | `node-red` |
| `/var/lib/AdGuardHome` | root, and note the capitals |

Importing the named volumes:

```sh
for v in dawarich_dawarich_db_data ... ; do
  podman volume create $v
  podman volume import $v ~/migration/$v.tar
done
```

One line of Home Assistant's configuration needs changing. In
`/var/lib/hass/configuration.yaml`:

```yaml
http:
  trusted_proxies: [192.168.116.119]   # the old Caddy container
```

becomes `127.0.0.1`, since Caddy is now on the same host. Leave it and every request is rejected
with a 400, with no trace of why outside HA's own log.

### 5.1 Things that break because an address changed

A few places hardcode the old host's address. The services still start, so the discovery
happens when someone tries to use them.

| Where | What |
|---|---|
| `/var/lib/hass/configuration.yaml` | `trusted_proxies` to `127.0.0.1`, as above |
| `/var/lib/homelab/homepage/config/services.yaml` | 19 hardcoded addresses. `192.168.116.100` (pve, gone), `.88` (HAOS, now localhost), `.65` (CT101, now localhost). `.53` (the Pi) and `.91` stay |
| OwnTracks on the phone | Points at Dawarich on the old CT101's `:3005`. Change it to the new host |
| MQTT clients | mosquitto's authentication moves from the HA user to its own |

### 5.1.1 What restoring needs must not live inside the backup

`/var/lib/secrets` is included in the restic backup, which means the restic password and the
rclone configuration have to exist outside the backup — in Bitwarden — or the backup cannot be
opened at all. Confirm they are to hand before migrating.

The Mac's `~/.ssh/config` is managed through sops and contains entries such as `pve`. Adding a
`homeserver` entry is work on that side.

### 5.2 Cleaning up the old snapshots, which can wait

pve sent its vzdump to Google Drive under `--host pve --tag pve-vzdump`. That host no longer
exists, so left alone they stay forever.

```sh
restic forget --host pve --tag pve-vzdump --keep-last 1 --prune
```

---

## 6. Verifying

```sh
systemctl --failed
journalctl -p err -b --no-pager | tail -40
```

- Does https://status.gapul.net go green? gatus watches twenty checks.
- Do the Matter devices come back online in Home Assistant? If not, suspect the host's IPv6
  first — Matter needs IPv6 even for Wi-Fi devices.
- Is Syncthing's device ID still `Y72TVZZ-...`? If it changed, the restore in 2.4 failed.
- Does `restic snapshots` from the Mac show a new snapshot tagged homeserver?
- Does `dig @<the new host> example.com` answer? AdGuard owns port 53.
- The company tunnel: `systemctl status mvrx-vpn`, `ip -4 addr show ppp0`, and whether
  `ssh mvrx-nolang-dev` works over the tailnet. This is the one thing CI could not verify, so
  if it fails, boot the disk image from 2.3.1 under libvirt and get work moving first.
- Does Jellyfin's hardware transcoding work? On bare metal `/dev/dri` shows up without effort.

Containers take a while the first time, pulling images. docker.io is already declared to go
through mirror.gcr.io, so the rate limit should not come up.

The stacks with databases — attic, dawarich, miniflux, paperless — die once on first start and
restart. The compose health wait becomes a systemd ordering dependency, which only knows that
the dependency started. `Restart=always` catches it, so leave it alone.

---

## 7. Rolling back

pve no longer exists, so going back means reinstalling Proxmox and restoring from section 2.
Several hours.

The realistic insurance is NixOS generations: if the problem is configuration, one reboot
selects the previous generation. ZFS snapshots are taken automatically, so if the problem is
data, `zfs rollback`.

What is gone is the console. There is no more noVNC into the machine from pve's web UI, so if it
stops booting, that means physical access. `systemctl reboot --firmware-setup` gets to the BIOS.
