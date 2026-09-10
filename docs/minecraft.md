# Running the Minecraft servers

Four Minecraft servers run on the mac mini instead of paying for Realms. They are declared in
`minecraftServers` in `nix/hosts/macmini.nix`, and the launch scripts live in
`configs/macmini/minecraft/`. This page is about where to look when you need to touch them.

## What is running

| Name | Public port | Version | Purpose |
|---|---|---|---|
| vanilla | 25565 | Paper 26.2, tracking latest | The main server, for playing with friends. Multiverse can add worlds. |
| solo | 25566 | Paper 26.2, tracking latest | Single player. Two worlds carried over from the Mac. |
| fabric | 25568 | Fabric 26.2 | Mods on the newest version |
| modded | 25567 | NeoForge 1.21.1 | Mods that never came to Fabric, such as Twilight Forest |

The way in from outside is a playit tunnel forwarding to the matching port on the mac mini.
From inside the tailnet, connect straight to `100.105.135.49:<port>`.

## Nothing runs while nobody plays

lazymc holds the public port; the server itself runs on loopback at port + 100. With nobody
connected the server is not running at all, and the idle cost is four lazymc processes, about
36 MB and no measurable CPU. A connection wakes the server and joins it through, which the
client sees as "starting". Startup measures four to five seconds, and it stops again after ten
idle minutes.

`freeze_process` is off. The default freeze, a SIGSTOP, resumes faster but keeps 1.2 GB
resident, and four of those is too much on a machine whose 24 GB is shared with the AI stack.

If lazymc is killed outright, the server underneath stays stopped while still holding the world
lock, and the next start fails with `already locked`. The launch script clears the stale lock
holder before starting, so this resolves itself.

## Adding and changing things

**Adding an instance** means one more entry in `minecraftServers`. lazymc, the daemon, its
priority, logging and backups all follow from the table. Pick a port that does not collide with
the others; port + 100 is used behind it.

**Adding a world** on the Paper side is `/mv create <name> normal` in game. Worlds are
generated data and never appear in the declaration. Do not put a hyphen in the name: 26.2 keys
worlds as `minecraft:<name>`, hyphens are not valid in that key, and Multiverse fails to import
the world.

**Adding a plugin or mod** means listing it under `env.PLUGINS` or `env.MODS` in
`minecraftServers`, pinned with `fetchurl`. `plugins/` and `mods/` are filled with symlinks into
the store, and removing an entry from the declaration removes the file on the next start.
Dropping a jar in by hand also works for experiments, and those are left alone.

Mods and plugins are not on the automatic update path. They catch up to new server versions at
very different speeds, and letting them move on their own produces "the world I played
yesterday will not open". Bumping them is a decision someone makes.

## Updating the servers

Only Paper is tracked, weekly. The `update-custom-packages` GitHub Action finds the newest
STABLE build, rewrites `nix/pkgs/paper-server.nix`, and moves `paperMcVersion` and
`paperProtocol` with it — the version lazymc reports while the server sleeps. The protocol
number is not in Paper's API, so it comes from minecraft-data; if that lookup fails the value
stays as it is and a message goes to standard error.

The mac mini pulls at 05:00 every morning, and a post-merge hook carries it through
`just rebuild`.

A version bump converts the worlds, and conversion is one-way. The launch script moves the
pre-conversion world aside to `<instance>.pre-<old version>` first, keeping one generation.

## Backups

Every night at 04:40 each instance is stopped in turn, archived, and kept for seven generations
in `/Users/Shared/minecraft-backups`. The restic run at 05:00 carries that directory offsite.

Besides the worlds, the archive takes `mods/`, `plugins/`, `config/`, `defaultconfigs/`,
`server.properties`, `whitelist.json` and `ops.json`. Declared jars can be restored from the
store, but hand-installed jars and per-mod configuration exist nowhere else.

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
