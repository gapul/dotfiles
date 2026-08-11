{
  # Blocky in place of AdGuard Home. AdGuard's settings were already declared
  # here, so this is not about declarativeness per se — it is that AdGuard keeps
  # half its state in a file it writes itself (the admin account, and anything
  # changed through the web UI), and reconciling that with nix means
  # mutableSettings = true and hoping the two agree. Blocky has no UI and no
  # writable state: the YAML below is the whole configuration.
  #
  # What is lost: the query log browser and the per-client rules page. Metrics
  # come out as Prometheus instead, and the API answers on :4000.
  #
  # The Raspberry Pi still runs AdGuard as the primary resolver, so DNS for the
  # house does not depend on this machine at all.
  services.blocky = {
    enable = true;
    settings = {
      # Only the loopback and this machine's own address — the podman bridges
      # need :53 for aardvark-dns. This is the same collision AdGuard hit.
      ports = {
        dns = "127.0.0.1:53,192.168.116.98:53";
        http = 4000; # metrics + API. dns2.gapul.net points here now.
      };

      upstreams.groups.default = [ "https://dns10.quad9.net/dns-query" ];
      # DoH cannot resolve its own hostname, so these have to be addresses.
      bootstrapDns = [
        { upstream = "9.9.9.10"; }
        { upstream = "149.112.112.10"; }
      ];

      blocking = {
        denylists.ads = [
          # The one list AdGuard had enabled. AdAway was present but disabled,
          # so it is not carried over.
          "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt"
        ];
        clientGroupsBlock.default = [ "ads" ];
        # NXDOMAIN rather than 0.0.0.0: clients stop retrying, and it does not
        # leave sockets hanging on a black hole.
        blockType = "nxDomain";
      };

      caching = {
        minTime = "5m";
        maxTime = "30m";
        prefetching = true;
      };

      prometheus.enable = true;
      # Queries are not logged to disk. AdGuard kept a searchable log; if that
      # turns out to be missed, set queryLog.type = "csv" and a path here.
      queryLog.type = "none";
      log.level = "info";
    };
  };

  # Port 53 is Blocky's; nothing else on this host may take it.
  services.resolved.enable = false;

  # DNS has to be reachable from the LAN, unlike everything else here: clients
  # point at this address directly.
  networking.firewall.allowedTCPPorts = [ 53 ];
  networking.firewall.allowedUDPPorts = [ 53 ];
}
