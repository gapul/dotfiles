{ pkgs, ... }:
let
  # Volunteer client for ActiveTK's uploader.jp archive (https://uploaderjp-full-archive.activetk.jp/),
  # added 2026-11-16. uploader.jp deletes everything at 2026-11-25 23:59 JST; remove this module after.
  #
  # Deliberately NOT the official ghcr.io/activetk/uploaderjp-client image: its boot.py pulls a signed
  # code bundle from the operator every 10 min and executes it, so the operator could run anything
  # here. This runs the published source.zip instead (client.py VERSION=2, stdlib only), read before
  # pinning. If the hub starts refusing this version, read the new source before bumping the hash.
  src = pkgs.fetchzip {
    url = "https://uploaderjp-full-archive.activetk.jp/dl/ujp-client-win-v1-source.zip";
    hash = "sha256-F6RNcdyRLqC1uuAE8tWa1U5MTx3h2oqVzQowr4gZ3js=";
    stripRoot = false;
  };
in
{
  systemd.services.ujp-archive = {
    description = "uploader.jp archive volunteer client";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    # client.py spawns `python3 -I dl.py` by name.
    path = [ pkgs.python3 ];
    environment = {
      UJP_DATA = "/var/lib/ujp-archive";
      UJP_NICK = "gapul";
    };
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 -I ${src}/client.py";
      # UJP_TOKEN (account token from the portal, so contributions count for the X login).
      EnvironmentFile = "/var/lib/secrets/ujp-archive.env";
      Restart = "always";
      RestartSec = "1min";
      DynamicUser = true;
      StateDirectory = "ujp-archive";
      WorkingDirectory = "/var/lib/ujp-archive";
      # Downloads arbitrary third-party files and talks to a stranger's server: keep it off the
      # LAN and tailnet entirely. DNS still works through nscd's socket. Egress bypasses Mullvad
      # (bypassUnits in mullvad-host.nix): Cloudflare blocked its shared address immediately.
      IPAddressDeny = [
        "localhost"
        "link-local"
        "multicast"
        "10.0.0.0/8"
        "172.16.0.0/12"
        "192.168.0.0/16"
        "100.64.0.0/10"
        "fc00::/7"
      ];
      CapabilityBoundingSet = "";
      LockPersonality = true;
      MemoryMax = "1G";
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectProc = "invisible";
      ProtectSystem = "strict";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      SystemCallArchitectures = "native";
    };
  };
}
