# Two AdGuard Home instances

Local DNS made redundant with a primary on a Raspberry Pi 4 and a secondary on `.65`. The Pi can
be switched off at any time for creative work, and the secondary keeps resolving names while it
is gone.

## The pieces

| Role | Host | DNS | Admin UI | External URL |
|---|---|---|---|---|
| Primary | Raspberry Pi 4, `192.168.116.53` | :53 | :3000 | `dns.gapul.net` |
| Secondary | The Docker host, `192.168.116.65` | :53 | :3080 | `dns2.gapul.net` |
| Sync | `.65`, adguardhome-sync | — | — | Primary to secondary, every 10 minutes |

```
client DNS settings:
  primary   = 192.168.116.53   the Pi. Safe to switch off
  secondary = 192.168.116.65   always up, and takes over
```

## Setting it up

### 1. Preparing the Pi

- Flash Raspberry Pi OS Lite, 64-bit, to a microSD card.
- Give it the fixed address `192.168.116.53`, either as a DHCP reservation on the router or
  through dhcpcd.
- Install Docker and the compose plugin.
- To make the card last: install `log2ram` and enable `zram`.

### 2. Starting the primary, on the Pi

```bash
cd configs/homelab/adguard/primary-pi
docker compose up -d
# then run the first-time setup at http://192.168.116.53:3000 and create the admin login
```

### 3. Starting the secondary, on `.65`, through Dockge or the CLI

```bash
cd configs/homelab/adguard/secondary
docker compose up -d
# first-time setup at http://192.168.116.65:3080, with the same admin
```

### 4. Starting the sync, on `.65`

```bash
cd configs/homelab/adguard/sync
cp .env.example .env   # fill in both admin passwords; sops is preferable
docker compose up -d
```

From then on, filters, rewrite rules and settings edited on the primary are copied to the
secondary automatically.

### 5. Handing it to the clients

Set the router's DHCP-distributed DNS to both `192.168.116.53` and `192.168.116.65`. Over
Tailscale this coexists with the existing split DNS that sends `gapul.net` to Cloudflare.

## Switching the Pi off and back on

```bash
# stop it, on the Pi. The secondary at .65 takes over DNS automatically.
docker compose -f primary-pi/compose.yaml down
sudo systemctl disable docker   # also stop Docker entirely, to free resources during creative work

# ... CPU, memory and IO are all yours

# bring it back
sudo systemctl enable --now docker
docker compose -f primary-pi/compose.yaml up -d
# the next sync cycle reconciles it with the secondary
```

`conf/` lives in a volume, so settings and logins survive being stopped.

## Notes

- `work/`, `conf/` and `.env` are outside git, already in `.gitignore`. Neither the real
  configuration nor the secrets get committed.
- Do not use the DHCP server feature on either instance. It is not synced, and the router keeps
  doing DHCP.
- Tailscale can stay running during creative work; it is light and it is how you get in.
