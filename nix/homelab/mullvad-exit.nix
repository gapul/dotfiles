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
    # Declared but not running: the Mullvad account expired on 2026-08-03 and is
    # not being renewed for now. Set to true (and re-register the WireGuard key
    # via the Mullvad devices API) when the exit node is wanted again.
    autoStart = false;
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

        networking.wg-quick.interfaces.mullvad = {
          autostart = true;
          configFile = "/var/lib/secrets/mullvad-exit.conf";
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
