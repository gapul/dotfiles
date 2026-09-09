# Forgejo, a git host at home that is not GitHub

A redundant remote, so dotfiles and the rest of the code are still at home if GitHub goes down
or the account is frozen.

Published at `https://git.gapul.net/`, through Caddy, on Tailscale only, with TLS from
Cloudflare DNS-01. git is HTTPS only, with SSH disabled, and push and pull authenticate with a
token.

## Deploying, on CT101, dockge, at .65

```bash
ssh proxmox            # root@192.168.116.100; retry if the path flaps
pct enter 101
mkdir -p /opt/stacks/forgejo/data && cd /opt/stacks/forgejo
# put compose.yaml in place, from configs/homelab/forgejo/compose.yaml. The Dockge UI is easier.
docker compose up -d
docker compose logs -f          # wait for "Starting new Web server"
```

## Applying the Caddy route, on CT103

`configs/homelab/caddy/Caddyfile` already routes `git.gapul.net` to `.65:3003`. Distribute it to
the Caddy container and reload:

```bash
ssh proxmox 'pct exec 103 -- caddy reload --config /etc/caddy/Caddyfile'
```

## First-time setup, in the browser

1. Open `https://git.gapul.net/` and you get the setup screen.
2. Create the admin user, `gapul`. The built-in SQLite is plenty.
3. Under Settings, Applications, choose Generate New Token with the repo scope, and put the
   token in Bitwarden.

## Two ways to make a repository redundant

### Pull mirror, recommended, because nothing on the Mac changes

Forgejo pulls from GitHub periodically and keeps a copy at home. Nothing on the Mac needs
changing.

1. Plus, top right, then New Migration, then GitHub.
2. Give the GitHub repo URL, for instance `https://github.com/gapul/dotfiles`.
3. Tick "This repository will be a mirror", then Migrate.
4. For a private repository, paste a GitHub token.
5. From then on it syncs on the configured interval, and
   `git.gapul.net/gapul/dotfiles` always holds a current copy.

Registering dotfiles, notes and the like this way means pushes still go to GitHub while a copy
stays at home.

### Pushing to both, making home a live mirror

Point the Mac's repository at both remotes:

```bash
cd ~/.dotfiles
# create an empty repository in Forgejo first, through New Repository, then:
git remote set-url --add --push origin https://git.gapul.net/gapul/dotfiles.git
git remote set-url --add --push origin https://github.com/gapul/dotfiles.git   # re-add the existing one
# from now on `git push` goes to both. The token lives in the git credential helper or .netrc
git config credential.https://git.gapul.net.username gapul
```

## Maintenance

Back up `./data`, which holds the SQLite database and the repositories themselves, separately.
It is not covered by the Mac's restic, so either dump it periodically from the homelab side, or
accept that GitHub holds the original of anything important and Forgejo can be rebuilt.

For updates, wud reports a new version and Dockge pulls and redeploys.
