{ config, ... }:
let
  dnsCertDir = config.security.acme.certs."dns.gapul.net".directory;
in
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
      # DNS over TLS for nixos-laptop, which puts this resolver first in its own ordered list
      # and keeps every server there on strict TLS (hosts/nixos-laptop.nix).
      tls = {
        listen = "127.0.0.1:853,192.168.116.98:853,100.127.129.31:853";
        certFile = "${dnsCertDir}/fullchain.pem";
        keyFile = "${dnsCertDir}/key.pem";
      };
    };
  };

  # Its own cert for the one name, not the *.gapul.net wildcard Caddy uses: macmini's blocky
  # serves the same name with a cert it issues itself, and neither host needs the other's key.
  # Same Cloudflare DNS-01 credential as the wildcard (homeserver.nix).
  security.acme.certs."dns.gapul.net" = {
    dnsProvider = "cloudflare";
    environmentFile = "/var/lib/secrets/acme-cloudflare.env";
    group = "dns-tls";
    # blocky reads the files once at start.
    reloadServices = [ "blocky.service" ];
  };
  users.groups.dns-tls = { };
  systemd.services.blocky = {
    # DynamicUser, so the cert's group is added as a supplementary one.
    serviceConfig.SupplementaryGroups = [ "dns-tls" ];
    # The preliminary self-signed cert covers the first boot; ordering keeps a restart from
    # racing a renewal (as for Caddy).
    after = [ "acme-finished-dns.gapul.net.target" ];
    wants = [ "acme-finished-dns.gapul.net.target" ];
  };

  # tailscale0 comes up after blocky. Since it listens on the tailnet address by name, it can fail at
  # startup with "cannot bind to an address that doesn't exist yet", so allow binding to non-local
  # addresses. Ordering with After= is another option, but it can't cover tailscaled re-assigning the
  # address on reconnect.
  boot.kernel.sysctl."net.ipv4.ip_nonlocal_bind" = 1;

  # Port 53 belongs to Blocky. Nothing else gets it on this host.
  services.resolved.enable = false;
  # The host's own resolver (MagicDNS is off, see services.tailscale in hosts/homeserver.nix).
  # The LAN address rather than 127.0.0.1: podman drops loopback servers when it hands
  # resolv.conf to containers and falls back to a public resolver, while this address is
  # reachable from them and still never leaves the box. macmini's blocky only on timeout, in
  # plaintext over the tailnet, so that a dead local blocky doesn't cut off self-deploy.
  networking.nameservers = [
    "192.168.116.98"
    "100.105.135.49"
  ];
  # The one MagicDNS name used here (paperless's OCR endpoint): its certificate is for that name,
  # so an IP will not do. Same approach as nixos-laptop.
  networking.hosts."100.105.135.49" = [ "macmini.tail079f44.ts.net" ];

  # This one must be reachable from the LAN. Clients point at this address directly.
  networking.firewall.allowedTCPPorts = [
    53
    853
  ];
  networking.firewall.allowedUDPPorts = [ 53 ];
}
