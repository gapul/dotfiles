# Dedicated Terraria server. The world's source of truth is here; characters are left to each
# player's Steam Cloud (on the workstation, restic also picks up Steam/userdata). TShock's
# server-side characters are not used: the goal is just to keep the world in one place, and
# there's no need to guard against cheated-in items.
#
# It lives here rather than next to the macmini's Minecraft because nixpkgs' terraria-server is
# x86_64-linux only and NixOS has this module. The server is single-threaded and a few hundred MB,
# so it doesn't need a sleep mechanism like lazymc.
#
# Reachable only over the tailnet (the firewall trusts tailscale0). To let in friends from
# outside, point playit at 7777 as with Minecraft. The world is auto-generated in
# /var/lib/terraria/.local/share/Terraria/Worlds and goes to restic along with /var/lib in
# backup.nix. Console: `tmux -S /var/lib/terraria/terraria.sock attach`.
{ lib, ... }:
{
  # terraria-server is unfree (Re-Logic's redistributable binary). It is the only unfree package
  # allowed on this host, so, like permittedInsecurePackages in matrix-bridges.nix, it sits in the
  # module that uses it.
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "terraria-server" ];

  services.terraria = {
    enable = true;
    port = 7777;
    maxPlayers = 8;
    # If omitted, -world is not passed and the server sits at the interactive "Choose World:" prompt
    # and never listens (this actually happened on the first switch on 2026-09-26). With an explicit
    # path, together with -autocreate it creates the world if missing. The module prepares the
    # directory via tmpfiles.
    worldPath = "/var/lib/terraria/.local/share/Terraria/Worlds/world.wld";
    autoCreatedWorldSize = "medium";
    messageOfTheDay = "homeserver terraria";
    # tailnet only. Anything wider goes through playit, not the LAN firewall.
    openFirewall = false;
    noUPnP = true;
  };
}
