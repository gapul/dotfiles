# All of this host's outbound traffic goes through Mullvad (device "mellow panda",
# jp-tyo-wg-202), except a short list of destinations that keep the house's address.
#
# Not the Tailscale exit node on homeserver (homelab/mullvad-exit.nix): this host's
# tailscaled is the open-source daemon, which on macOS accepts --exit-node but never
# installs the default route, so traffic kept leaving over en0. A WireGuard tunnel of
# its own instead, from wg-quick, which points 0/1 and 128/1 at the tunnel.
#
# tailscaled binds its sockets to en0. With the tunnel up and no en0-scoped default
# route, every one of those binds failed ("network is unreachable"): no UDP, DERP
# only, peers relayed. Adding `-ifscope en0 default` keeps tailscaled on the plain
# line with direct connections, and everything else in the tunnel (2026-10-31).
#
# IPv4 only: this host has never had an IPv6 default route (macmini-dns.nix), and
# carrying ::/0 would give it IPv6 through Mullvad alone, which the exceptions
# below could not follow.
#
# Not a kill switch. If the tunnel is down, traffic goes out the plain line.
#
# The key is registered on the Mullvad account (devices API); if the account lapses
# the key is deleted with it and must be registered again, and the address below
# replaced with the one Mullvad returns.
{ config, pkgs, ... }:
let
  # Kept on the plain line, resolved every pass and pinned as host routes.
  # Banks and member sites flag or block VPN addresses, and these sessions are
  # signed in unattended (home/macmini-revolut.nix, home/macmini-sites.nix).
  bypassHosts = [
    "app.revolut.com"
    "revolut.com"
    "sso.revolut.com"
    "www.revolut.com"
    "id.jreast.co.jp"
    "mobilesuica.com"
    "www.mobilesuica.com"
    "www.jrepoint.jp"
    "www.biccamera.com"
  ];
  # cloudflared's edge (region1/region2.v2.argotunnel.com) for the presenta tunnel
  # (macmini-presenta.nix). Through Mullvad it cannot reach port 7844; the same was
  # measured on homeserver (homelab/mullvad-host.nix).
  bypassNets = [
    "198.41.192.0/24"
    "198.41.200.0/24"
  ];

  keyFile = config.sops.secrets."mullvad/private_key".path;
  runDir = "/var/run/mullvad";
  conf = "${runDir}/mullvad.conf";

  wgPath = pkgs.lib.makeBinPath [
    pkgs.wireguard-tools
    pkgs.wireguard-go
    pkgs.bash
  ];

  daemon = pkgs.writeShellScript "mullvad-tunnel" ''
    set -u
    export PATH=${wgPath}:/usr/bin:/bin:/usr/sbin:/sbin

    mkdir -p ${runDir}
    umask 077
    cat > ${conf} <<EOF
    [Interface]
    PrivateKey = $(cat ${keyFile})
    Address = 10.164.248.237/32

    [Peer]
    PublicKey = 3NykAEXAdeaT0qFstBkJorW3PDsBRUHHbBUc6YoIzAs=
    Endpoint = 146.70.201.130:51820
    AllowedIPs = 0.0.0.0/0
    PersistentKeepalive = 25
    EOF

    trap 'wg-quick down ${conf}; exit 0' TERM INT
    # A tunnel left by an earlier run would make `up` refuse.
    wg-quick down ${conf} >/dev/null 2>&1
    wg-quick up ${conf}

    while :; do
      gw=$(ipconfig getoption en0 router 2>/dev/null)
      if [ -n "$gw" ]; then
        netstat -rn -f inet | awk '$1 == "default" && $NF == "en0" && $3 ~ /I/ { found = 1 } END { exit !found }' \
          || route -q -n add -inet -ifscope en0 default "$gw"
        for net in ${toString bypassNets}; do
          route -q -n add -inet -net "$net" "$gw" >/dev/null 2>&1
        done
        for host in ${toString bypassHosts}; do
          for addr in $(dig +short +time=3 +tries=1 A "$host" | grep -E '^[0-9.]+$'); do
            route -q -n add -inet -host "$addr" "$gw" >/dev/null 2>&1
          done
        done
      fi
      [ -e /var/run/wireguard/mullvad.name ] || wg-quick up ${conf}
      sleep 120 &
      wait $!
    done
  '';
in
{
  sops.secrets."mullvad/private_key".sopsFile = ../../secrets/macmini.yaml;

  launchd.daemons.mullvad-tunnel = {
    # `command` so nix-darwin prepends `wait4path /nix/store` (see the Minecraft daemons).
    command = "${daemon}";
    serviceConfig = {
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/var/log/mullvad-tunnel.log";
      StandardErrorPath = "/var/log/mullvad-tunnel.log";
    };
  };
}
