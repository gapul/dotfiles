{ pkgs, ... }:
let
  hostPkgs = pkgs;
  mullvadEndpoint = "138.199.21.239";
  mullvadPort = 51820;
in
{
  # A second Tailscale node whose default route is Mullvad. Keep it inside a
  # NixOS container so the WireGuard policy routes and kill switch can never
  # rewrite the homeserver's own network namespace.
  containers.mullvad-exit = {
    # If the Mullvad account lapses, the device keys are deleted with it: set this
    # to false, and on renewal re-register the conf's key via the Mullvad devices
    # API and put the addresses it returns into the conf.
    autoStart = true;
    privateNetwork = true;
    hostAddress = "10.233.0.1";
    localAddress = "10.233.0.2";
    enableTun = true;

    bindMounts = {
      "/var/lib/secrets/tailscale.key" = {
        hostPath = "/var/lib/secrets/tailscale.key";
        isReadOnly = true;
      };
      "/var/lib/secrets/mullvad-exit.conf" = {
        hostPath = "/var/lib/secrets/mullvad-exit.conf";
        isReadOnly = true;
      };
    };

    config =
      { lib, pkgs, ... }:
      {
        nixpkgs.pkgs = hostPkgs;

        networking = {
          useHostResolvConf = lib.mkForce false;
          nameservers = [ "10.64.0.1" ];

          # The kill switch lives in mangle, before Tailscale's filter chains.
          # It does not ACCEPT forwarded packets itself: Tailscale must still
          # apply its own marks and SNAT. It only rejects the two leak paths,
          # local or forwarded traffic selecting the clearnet eth0 interface.
          firewall = {
            allowedUDPPorts = [ 41641 ];
            extraCommands = ''
              iptables -t mangle -C OUTPUT -o eth0 -j DROP 2>/dev/null || iptables -t mangle -I OUTPUT 1 -o eth0 -j DROP
              iptables -t mangle -C OUTPUT -o eth0 -d ${mullvadEndpoint}/32 -p udp --dport ${toString mullvadPort} -j ACCEPT 2>/dev/null \
                || iptables -t mangle -I OUTPUT 1 -o eth0 -d ${mullvadEndpoint}/32 -p udp --dport ${toString mullvadPort} -j ACCEPT
              iptables -t mangle -C FORWARD -i tailscale0 -o eth0 -j DROP 2>/dev/null \
                || iptables -t mangle -I FORWARD 1 -i tailscale0 -o eth0 -j DROP
            '';
          };
        };

        # The conf must carry `FwMark = 51820`: wg-quick only sets a fwmark itself
        # with Table = auto, and without it the PostUp rule `not fwmark 51820`
        # routes WireGuard's own encapsulated packets back into the tunnel (seen
        # 2026-10-30: handshakes worked, gigabytes sent, nothing received).
        networking.wg-quick.interfaces.mullvad = {
          autostart = true;
          configFile = "/var/lib/secrets/mullvad-exit.conf";
        };

        # The conf's `pref 5000 not fwmark 51820` rule comes before Tailscale's
        # table 52, so this node's own packets to tailnet addresses went into
        # Mullvad. That broke its MagicDNS (100.100.100.100 forwards to the blocky
        # resolvers on the tailnet), and with it DNS for every client using this
        # exit node. Send the tailnet ranges to Tailscale's table first.
        systemd.services.tailnet-before-mullvad = {
          wantedBy = [ "multi-user.target" ];
          before = [ "wg-quick-mullvad.service" ];
          path = [ pkgs.iproute2 ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            ip -4 rule add pref 4990 to 100.64.0.0/10 lookup 52 2>/dev/null || true
            ip -6 rule add pref 4990 to fd7a:115c:a1e0::/48 lookup 52 2>/dev/null || true
          '';
        };

        services.tailscale = {
          enable = true;
          openFirewall = true;
          useRoutingFeatures = "server";
          authKeyFile = "/var/lib/secrets/tailscale.key";
          # Passed to `tailscale up` rather than `tailscale set`: tailscaled-set would
          # otherwise run before the login below has happened.
          extraUpFlags = [
            "--hostname=mullvad-exit"
            "--advertise-exit-node"
          ];
        };

        # nspawn runs with --notify-ready=yes and the host configures its end of the
        # veth (link up, address, route) in ExecStartPost, i.e. only after the
        # container's boot transaction has completed. tailscaled-autoconnect is
        # Type=notify and stays in that transaction until the login succeeds, which
        # needs the network: a deadlock that ends in the 1 min start timeout and a
        # restart loop. Type=simple lets the boot finish while the login keeps
        # retrying in the background. NotifyAccess keeps the socket the upstream
        # script's `systemd-notify --ready` expects.
        systemd.services.tailscaled-autoconnect.serviceConfig = {
          Type = lib.mkForce "simple";
          NotifyAccess = "all";
        };

        # Do not bring up the exit node until the Mullvad policy route and kill
        # switch are installed. Losing wg-quick stops tailscaled as well.
        systemd.services.tailscaled = {
          after = [ "wg-quick-mullvad.service" ];
          requires = [ "wg-quick-mullvad.service" ];
        };

        environment.systemPackages = [
          pkgs.tailscale
          pkgs.wireguard-tools
        ];

        system.stateVersion = "26.05";
      };
  };

  # Clearnet is only a transport for the encrypted WireGuard packets. The
  # container kill switch prevents Tailscale payloads from using this NAT path.
  networking.nat = {
    enable = true;
    externalInterface = "enp2s0";
    internalInterfaces = [ "ve-mullvad-exit" ];
  };

}
