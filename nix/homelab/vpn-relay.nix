{
  pkgs,
  lib,
  ...
}:
let
  # Everything about the connection except one field. This is ordinary IKEv1
  # transport-mode L2TP configuration; only `right` — the office's VPN
  # concentrator — identifies an employer, so that alone is substituted at
  # runtime from /var/lib/secrets/mvrx/peer.
  ipsecConfTemplate = pkgs.writeText "ipsec.conf.in" ''
    config setup
        charondebug="ike 1, knl 1, cfg 0"
        uniqueids=no

    conn mvrx
        keyexchange=ikev1
        authby=secret
        type=transport
        left=%defaultroute
        leftprotoport=17/1701
        right=@MVRX_PEER@
        rightprotoport=17/1701
        ike=aes256-sha1-modp1024,aes128-sha1-modp1024,3des-sha1-modp1024,aes256-sha256-modp2048
        esp=aes256-sha1,aes128-sha1,3des-sha1,aes256-sha256
        keyingtries=%forever
        dpddelay=30
        dpdtimeout=120
        dpdaction=restart
        auto=add
  '';

  # nixpkgs keeps strongswan's configuration in the store and passes the location
  # in STRONGSWAN_CONF; there is no /etc/strongswan.conf. Anything that runs
  # `ipsec` without that variable aborts looking for one, which is how a working
  # charon kept getting torn down by the tunnel unit.
  #
  # This is a hand-written copy rather than the module's because starter has to
  # read a file that does not exist at build time.
  strongswanConf = pkgs.writeText "strongswan.conf" ''
    charon {
      plugins {
        stroke {
          secrets_file = /var/lib/secrets/mvrx/ipsec.secrets
        }
      }
    }

    starter {
      config_file = /run/mvrx/ipsec.conf
    }
  '';

  mkIpsecConf = pkgs.writeShellScript "mvrx-ipsec-conf" ''
    set -eu
    install -d -m 700 /run/mvrx
    ${pkgs.gnused}/bin/sed "s|@MVRX_PEER@|$(cat /var/lib/secrets/mvrx/peer)|" \
      ${ipsecConfTemplate} > /run/mvrx/ipsec.conf
    chmod 600 /run/mvrx/ipsec.conf
  '';
in
{
  # What VM105 (mvrx-vpn-relay) did: dial the office over L2TP/IPsec and let the
  # tailnet reach the corporate subnet through it, so working from home needs no
  # VPN client on the laptop.
  #
  # It is safe to run this on the machine that serves everything else, which was
  # checked rather than assumed: pppd here is configured without `defaultroute`,
  # so ppp0 only ever carries the one corporate subnet and the house's default
  # route is untouched. An exit node would be a different story, which is why
  # CT106 is not folded in here.
  #
  # Nothing about the office is in this repo. The peer address, the PSK, the
  # account and the host the watchdog probes live in /var/lib/secrets/mvrx/;
  # see README.md for the files.
  #
  # This is also the one part CI cannot verify — there is no office endpoint to
  # dial from a sandboxed VM. Keep the exported VM105 disk image until the tunnel
  # has come up here at least once.

  environment.systemPackages = with pkgs; [
    strongswan
    xl2tpd
    ppp
  ];

  services.strongswan.enable = true;
  systemd.services.strongswan = {
    # Point the daemon at the hand-written config, and materialise the connection
    # (with the peer filled in) before it starts. ExecStartPre is prefixed with +
    # so it runs privileged enough to read the secret.
    environment.STRONGSWAN_CONF = lib.mkForce "${strongswanConf}";
    serviceConfig.ExecStartPre = [ "+${mkIpsecConf}" ];
  };

  # pppd has its chap-secrets path compiled in, so this one has to be in /etc.
  systemd.tmpfiles.rules = [
    "d /var/lib/secrets/mvrx 0700 root root -"
    "L+ /etc/ppp/chap-secrets - - - - /var/lib/secrets/mvrx/chap-secrets"
  ];

  systemd.services.mvrx-vpn = {
    description = "MVRX L2TP/IPsec tunnel (subnet router uplink)";
    after = [
      "network-online.target"
      "strongswan.service"
    ];
    wants = [ "network-online.target" ];
    requires = [ "strongswan.service" ];
    path = with pkgs; [
      strongswan
      xl2tpd
      ppp
      iproute2
      coreutils
    ];
    # Don't let a failing tunnel retry forever; retrying is the watchdog's job.
    startLimitIntervalSec = 600;
    startLimitBurst = 3;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    environment.STRONGSWAN_CONF = "${strongswanConf}";
    # No `ipsec restart` here. strongswan is a service of its own now; restarting
    # it from inside this unit tore down a working daemon and replaced it with
    # one that could not find its configuration.
    #
    # The sleeps are not decoration: each step has to be established before the
    # next is attempted. xl2tpd is driven through its control socket, the same
    # way the machine being replaced did it.
    script = ''
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

  # The tunnel drops without saying so, so something has to notice. Probing a
  # host on the far side rather than the interface, because ppp0 can exist while
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
      # that fell off the network every two minutes: each run restarted ipsec,
      # and that is disruptive enough to drop ssh with it.
      OnUnitActiveSec = "10min";
    };
    wantedBy = [ "timers.target" ];
  };
}
