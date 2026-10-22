# Dedicated Terraria server. The world's source of truth is here; characters are left to each
# player's Steam Cloud (on the workstation, restic also picks up Steam/userdata). TShock's
# server-side characters are not used: the goal is just to keep the world in one place, and
# there's no need to guard against cheated-in items.
#
# It lives here rather than next to the macmini's Minecraft because nixpkgs' terraria-server is
# x86_64-linux only and NixOS has this module.
#
# The server is not resident. Even with nobody connected it ticks the world and kept ~5% of a
# core busy around the clock (42k CPU-seconds over 9 days, measured 2026-10-13), on a fanless
# N150. So, like lazy-http-services.nix, systemd owns the public port 7777 and the first
# connection starts the server on 17777 behind systemd-socket-proxyd. The proxy exits after
# idleTimeout without connections (a player holds one TCP connection for the whole session),
# and StopWhenUnneeded then stops the server; the module's ExecStop sends `exit`, which saves
# the world. The first join after sleep waits while the world loads; if the client gives up,
# joining again works.
#
# Reachable only over the tailnet (the firewall trusts tailscale0). To let in friends from
# outside, point playit at 7777 as with Minecraft. The world is auto-generated in
# /var/lib/terraria/.local/share/Terraria/Worlds and goes to restic along with /var/lib in
# backup.nix. Console: `tmux -S /var/lib/terraria/terraria.sock attach` (only while awake).
{ lib, pkgs, ... }:
let
  publicPort = 7777;
  upstreamPort = 17777;
  idleTimeout = "15min";
  startupTimeout = 180;

  # Type=forking via tmux reports "started" long before the world is loaded and the port is
  # listening, so hold the first client on the systemd socket until a TCP connect succeeds.
  waitForUpstream = pkgs.writeShellApplication {
    name = "terraria-proxy-wait";
    bashOptions = [ ];
    text = ''
      deadline=$((SECONDS + ${toString startupTimeout}))
      while [ "$SECONDS" -lt "$deadline" ]; do
        (exec 3<>/dev/tcp/127.0.0.1/${toString upstreamPort}) 2>/dev/null && exit 0
        ${pkgs.coreutils}/bin/sleep 0.5
      done
      echo "terraria-proxy: upstream did not become ready within ${toString startupTimeout}s" >&2
      exit 1
    '';
  };
in
{
  # terraria-server is unfree (Re-Logic's redistributable binary). It is the only unfree package
  # allowed on this host, so, like permittedInsecurePackages in matrix-bridges.nix, it sits in the
  # module that uses it.
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "terraria-server" ];

  services.terraria = {
    enable = true;
    # The internal port. Players connect to publicPort, which the socket below owns.
    port = upstreamPort;
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

  systemd = {
    # Only the proxy may wake the server, and it goes back to sleep once the proxy is gone.
    services.terraria = {
      wantedBy = lib.mkForce [ ];
      unitConfig.StopWhenUnneeded = true;
    };

    sockets.terraria-proxy = {
      description = "Wake Terraria on incoming connections";
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = toString publicPort;
        NoDelay = true;
      };
    };

    services.terraria-proxy = {
      description = "On-demand proxy for Terraria";
      requires = [ "terraria.service" ];
      after = [ "terraria.service" ];
      serviceConfig = {
        Type = "simple";
        ExecStartPre = lib.getExe waitForUpstream;
        ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd --exit-idle-time=${idleTimeout} 127.0.0.1:${toString upstreamPort}";
        DynamicUser = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
      };
    };
  };
}
