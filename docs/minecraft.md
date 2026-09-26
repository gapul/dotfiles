# Running the Minecraft servers

Two Minecraft servers run on the mac mini instead of paying for Realms. They are declared in
`minecraftServers` in `nix/hosts/macmini.nix`, and the launch scripts live in
`configs/macmini/minecraft/`. This page is about where to look when you need to touch them.

## What is running

| Name | Public port | Version | Purpose |
|---|---|---|---|
| vanilla | 25565 | Fabric 26.2, tracking latest | The main server, for playing with friends. |
| solo | 25566 | Fabric 26.2, tracking latest | Single player. Same build, own whitelist, sleeps after an hour. |

Both run Fabric with server-side mods only (Fabric API plus the Lithium / FerriteCore / Krypton /
Moonrise performance set), so a plain launcher joins either one. Fabric replaced Paper on
2026-09-26 for one reason: the game version can move the day Mojang ships, where Paper's stable
builds trail by weeks, and the mods above make it as fast as Paper was. Nothing that needs a
client mod goes on these two; a modpack world is a separate, temporary instance (the NeoForge /
Twilight Forest one was retired on 2026-09-25, its world is in the backups directory).

The way in from outside is a playit tunnel forwarding to the matching port on the mac mini.
From inside the tailnet, connect straight to `100.105.135.49:<port>`.

## Nothing runs while nobody plays

lazymc holds the public port; the server itself runs on loopback at port + 100. With nobody
connected the server is not running at all, and the idle cost is two lazymc processes, about
18 MB and no measurable CPU. A connection wakes the server and joins it through, which the
client sees as "starting". Startup measures four to five seconds, and it stops again after ten
idle minutes (an hour on solo).

`freeze_process` is off. The default freeze, a SIGSTOP, resumes faster but keeps 1.2 GB
resident, and two of those is too much on a machine whose 24 GB is shared with the AI stack.

If lazymc is killed outright, the server underneath stays stopped while still holding the world
lock, and the next start fails with `already locked`. The launch script clears the stale lock
holder before starting, so this resolves itself.

## Adding and changing things

**Adding an instance** means one more `fabricInstance { dir; port; }` entry in
`minecraftServers`. lazymc, the daemon, its priority, logging and backups all follow from the
table. Pick a port that does not collide with the others; port + 100 is used behind it.

**Adding a world** is a datapack dimension (vanilla's own mechanism, no mod). Worlds are
generated data and never appear in the declaration.

**Adding a mod** means one more `# modrinth:<project id> <slug>` entry in
`nix/pkgs/fabric-mods.nix`; the updater fills in the file, URL and hash. `mods/` is filled with
symlinks into the store, and removing an entry removes the file on the next start. Dropping a
jar in by hand also works for experiments, and those are left alone. Only server-side mods
belong here; anything a client would have to install turns the server into a modpack server.

## Updating the servers

The `update-custom-packages` GitHub Action runs hourly. It takes the newest stable game version
for which *every* mod in `fabric-mods.nix` has a release, and rewrites `nix/pkgs/fabric-server.nix`
(game, loader, installer, hash) and `fabric-mods.nix` (one release per mod) for it. A new game
version is therefore adopted only once the whole set has caught up; until then loader and mod
releases for the current version still flow. `mcProtocol` — what lazymc reports while the server
sleeps — comes from minecraft-data; if that lookup fails it stays as it is and a message goes to
standard error.

The mac mini pulls at 05:30 every morning, and a post-merge hook carries it through
`just rebuild`.

A version bump converts the worlds, and conversion is one-way. The launch script moves the
pre-conversion world aside to `<instance>.pre-<old version>` first, keeping one generation.

## Backups

Every night at 04:40 each instance is stopped in turn, archived, and kept for seven generations
in `/Users/Shared/minecraft-backups`. The restic run at 05:00 carries that directory offsite.

Besides the worlds, the archive takes `mods/`, `config/`, `server.properties`, `whitelist.json`
and `ops.json`. Declared jars can be restored from the store, but hand-installed jars and per-mod
configuration exist nowhere else.

To restore, stop the instance and unpack the tar over its directory.

```bash
sudo launchctl bootout system/org.nixos.minecraft-solo
sudo -u mcsrv tar xzf /Users/Shared/minecraft-backups/solo-<date>.tar.gz -C /Users/mcsrv/solo
sudo launchctl bootstrap system /Library/LaunchDaemons/org.nixos.minecraft-solo.plist
```

## Bringing in an old world

A single-player world can be dropped in as it is and will be converted on startup. Worlds old
enough to have no DataVersion, meaning 1.9 and earlier, are refused by 26.2, which asks you to
open them in an older version first. Passing them through a 1.12.2 server once fixes that.
1.12.2 needs Java 8, so use `zulu8`.

Inventory and coordinates live in `playerdata` inside the world — `players/data` in 26.2 — so
moving the folder carries them along.

## Where to look when something breaks

- `<instance>/logs/launchd.log` for what lazymc decided: woken, slept, failed.
- `<instance>/logs/latest.log` for the server itself.
- If it will not accept connections from outside, suspect the Application Firewall. It
  remembers permission per binary, so a new store path for lazymc silently loses the grant.
  Activation re-registers it every time, but this is the thing to check. It fails in a
  confusing way: loopback still works, so the server looks healthy.
