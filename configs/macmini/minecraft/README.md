# minecraft

Everything to do with starting the Minecraft servers that run on the mac mini. Which instances
exist is decided by `minecraftServers` in `nix/hosts/macmini.nix`; what lives here is only the
scripts that table calls.

- `run.sh` — starts Paper and Fabric. If the version has changed it moves the world aside, then
  relinks the declared jars into `plugins/` and `mods/` before starting.
- `run-modded.sh` — starts NeoForge, running the installer once if the libraries are missing.
- `backup.sh` — every night at 04:40, stops each instance in turn and archives it.

How it is all put together, how to add a world and how to restore one are in
[`docs/minecraft.md`](../../../docs/minecraft.md).
