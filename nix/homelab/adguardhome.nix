{
  # AdGuard Home, secondary. The primary stays on the Raspberry Pi at .53, which
  # is the reason this machine dying does not take the house's DNS with it.
  #
  # Declared rather than clicked, which also retires adguardhome-sync: that
  # container existed only to copy settings from the primary to this one, and two
  # instances generated from the same nix need no copying. The Pi keeps its own
  # copy until it too runs NixOS.
  services.adguardhome = {
    enable = true;
    # Behind caddy as dns2.gapul.net; the old container published 3080 on the host
    # and 3000 inside, so keep the outside number.
    port = 3080;
    # The settings below are enforced on every start, but AdGuard is still allowed
    # to write its own file: the admin account lives in there, and a bcrypt hash
    # does not belong in a public repo. Set the password once in the web UI, the
    # same way tailscale and samba are authenticated by hand.
    mutableSettings = true;
    settings = {
      dns = {
        bind_hosts = [ "0.0.0.0" ];
        port = 53;
        upstream_dns = [ "https://dns10.quad9.net/dns-query" ];
        bootstrap_dns = [
          "9.9.9.10"
          "149.112.112.10"
          "2620:fe::10"
          "2620:fe::fe:10"
        ];
        enable_dnssec = true;
        upstream_mode = "load_balance";
      };
      filtering = {
        protection_enabled = true;
        safebrowsing_enabled = false;
      };
      filters = [
        {
          enabled = true;
          name = "AdGuard DNS filter";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt";
          id = 1;
        }
        {
          enabled = false;
          name = "AdAway Default Blocklist";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt";
          id = 2;
        }
      ];
    };
  };

  # Port 53 is AdGuard's. Nothing else on this host may take it.
  services.resolved.enable = false;

  # DNS has to be reachable from the LAN, not only over the tailnet: clients point
  # at this address directly. Everything else here stays tailscale-only.
  networking.firewall.allowedTCPPorts = [ 53 ];
  networking.firewall.allowedUDPPorts = [ 53 ];
}
