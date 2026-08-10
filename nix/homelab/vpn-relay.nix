{ pkgs, lib, ... }:
{
  # What VM105 (mvrx-vpn-relay) did: dial the office over L2TP/IPsec and let the
  # tailnet reach the corporate subnet through it, so working from home needs no
  # VPN client on the laptop.
  #
  # It is safe to run this on the machine that serves everything else, which is
  # not obvious and was checked rather than assumed: pppd here is configured
  # without `defaultroute`, so ppp0 only ever carries the one corporate subnet.
  # The house's default route is untouched. An exit node would be a different
  # story, which is why CT106 is not folded in here.
  #
  # Nothing about the office is in this repo. The peer address, the PSK, the
  # account and the host the watchdog probes all identify an employer's
  # infrastructure, so they live in /var/lib/secrets/mvrx/ and this file is only
  # the mechanism. Keys are listed in README.md.
  #
  # This is also the one part of the migration CI cannot verify — there is no
  # office endpoint to dial from a sandboxed VM. Keep the exported VM105 disk
  # image from the evacuation until the tunnel has come up here at least once;
  # booting that image under libvirt is the fallback that gets work unblocked in
  # minutes if this does not.

  # strongswan via the NixOS module rather than a hand-written unit. The
  # hand-rolled version failed two ways: nixpkgs' strongswan aborts with
  # "integrity test of libstrongswan failed" unless its own strongswan.conf
  # disables that check, and it never generated /etc/strongswan.conf at all
  # ("no files found matching"). The module handles both.
  #
  # The connection itself still comes from /var/lib/secrets/mvrx/, because it
  # names an employer's endpoint. setup/connections stay empty here and the
  # conn block is pulled in by the include in ipsec.conf below.
  services.strongswan = {
    enable = true;
    secrets = [ "/var/lib/secrets/mvrx/ipsec.secrets" ];
  };
  # The module writes ipsec.conf from `connections`; append the site-specific
  # block that cannot live in this repo.
  environment.etc."ipsec.conf".text = lib.mkForce ''
    config setup
        charondebug="ike 1, knl 1, cfg 0"
        uniqueids=no

    include /var/lib/secrets/mvrx/conn.conf
  '';

  environment.systemPackages = with pkgs; [
    strongswan
    xl2tpd
    ppp
  ];

  systemd.services.mvrx-vpn = {
    description = "MVRX L2TP/IPsec tunnel (subnet router uplink)";
    # Do not let a failing tunnel retry forever; the watchdog is what retries.
    startLimitIntervalSec = 600;
    startLimitBurst = 3;
    after = [
      "network-online.target"
      "strongswan.service"
    ];
    wants = [ "network-online.target" ];
    path = with pkgs; [
      strongswan
      xl2tpd
      ppp
      iproute2
      coreutils
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    # The sleeps are not decoration: each step has to be established before the
    # next is attempted, and this sequence is what is known to work against that
    # endpoint. xl2tpd is driven through its control socket, the same way the
    # machine being replaced did it.
    script = ''
      ipsec restart
      sleep 3
      ipsec up mvrx
      sleep 2
      mkdir -p /run/xl2tpd
      xl2tpd -c /var/lib/secrets/mvrx/xl2tpd.conf -D &
      sleep 2
      echo "c mvrx" > /run/xl2tpd/l2tp-control
      sleep 6
      ip -4 addr show ppp0 || echo "ppp0 not up"
      ip route | grep 192.168.1 || echo "no corp route"
    '';
    preStop = ''
      echo "d mvrx" > /run/xl2tpd/l2tp-control 2>/dev/null || true
      sleep 1
      ipsec down mvrx 2>/dev/null || true
    '';
    wantedBy = [ "multi-user.target" ];
  };

  # The tunnel drops without saying so, so something has to notice. Probing a host
  # on the far side rather than the interface, because ppp0 can exist while
  # nothing is reachable through it.
  systemd.services.mvrx-vpn-watchdog = {
    description = "MVRX VPN watchdog";
    path = with pkgs; [
      iproute2
      systemd
      bash
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      target="$(cat /var/lib/secrets/mvrx/probe-host)"
      if ! ip -4 addr show ppp0 >/dev/null 2>&1 \
        || ! timeout 5 bash -c "echo > /dev/tcp/$target" 2>/dev/null; then
        echo "tunnel down -> reconnecting"
        systemctl restart mvrx-vpn.service
      fi
    '';
  };
  systemd.timers.mvrx-vpn-watchdog = {
    timerConfig = {
      OnBootSec = "5min";
      # Was 120s, which turned a tunnel that could not come up into a machine
      # that fell off the network every two minutes: each run does `ipsec
      # restart`, and that is disruptive enough to drop ssh. Ten minutes still
      # reconnects a dropped tunnel quickly enough to matter, and a persistent
      # failure now costs a blip six times an hour instead of thirty.
      OnUnitActiveSec = "10min";
    };
    wantedBy = [ "timers.target" ];
  };
}
