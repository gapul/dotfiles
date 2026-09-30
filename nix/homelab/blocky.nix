{
  # Blocky in place of AdGuard Home. AdGuard's settings were declared here too, so this is not about
  # being declarative or not. AdGuard keeps half its state in files it writes itself (the admin account
  # and everything changed in the web UI), so meshing that with nix means setting mutableSettings = true
  # and praying the two agree.
  # Blocky has no UI and no written state. This YAML is the whole config.
  #
  # What we lose: browsing the query log and the per-client rules page. Metrics come out in
  # Prometheus format and the API answers on :4000.
  #
  # The secondary is macmini (hosts/macmini-dns.nix). Settings are shared via lib/blocky-settings.nix,
  # and the only difference from this machine is the listen addresses. This used to say "a Raspberry Pi
  # runs AdGuard as the primary resolver, so home DNS does not depend on this machine", but the Pi was
  # retired on 2026-08-24, and in the meantime this machine was the only
  # resolver.
  services.blocky = {
    enable = true;
    # Only loopback and this machine's own addresses. It can't be 0.0.0.0: the podman bridge
    # needs :53 for aardvark-dns. Same collision AdGuard ran into.
    #
    # The tailnet address is added too, so the tailnet DNS settings can point at this resolver;
    # without it, devices away from home can't reach the home blocky (neither ad blocking nor
    # internal resolution of gapul.net works).
    settings = import ../lib/blocky-settings.nix {
      listen = "127.0.0.1:53,192.168.116.98:53,100.127.129.31:53";
    };
  };

  # tailscale0 comes up after blocky. Since it listens on the tailnet address by name, it can fail at
  # startup with "cannot bind to an address that doesn't exist yet", so allow binding to non-local
  # addresses. Ordering with After= is another option, but it can't cover tailscaled re-assigning the
  # address on reconnect.
  boot.kernel.sysctl."net.ipv4.ip_nonlocal_bind" = 1;

  # Port 53 belongs to Blocky. Nothing else gets it on this host.
  services.resolved.enable = false;

  # This one must be reachable from the LAN. Clients point at this address directly.
  networking.firewall.allowedTCPPorts = [ 53 ];
  networking.firewall.allowedUDPPorts = [ 53 ];
}
