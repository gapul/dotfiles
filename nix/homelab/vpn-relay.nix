{
  pkgs,
  lib,
  ...
}:
let
  # Everything about the connection except one field. This is ordinary IKEv1
  # transport-mode L2TP configuration; only `right` — the remote site's VPN
  # concentrator — identifies the far end, so that alone is substituted at
  # runtime from /var/lib/secrets/l2tp/peer.
  ipsecConfTemplate = pkgs.writeText "ipsec.conf.in" ''
    config setup
        charondebug="ike 1, knl 1, cfg 0"
        uniqueids=no

    conn l2tp
        keyexchange=ikev1
        authby=secret
        type=transport
        left=%defaultroute
        # Not 17/1701. NAT-T rewrites the source port, so pinning it made the
        # far end drop quick mode without a word — five retransmits and
        # nothing back. With %any it answers.
        leftprotoport=17/%any
        right=@PEER@
        rightprotoport=17/1701
        ike=aes256-sha1-modp1024,aes128-sha1-modp1024,3des-sha1-modp1024,aes256-sha256-modp2048
        # PFS variants first. The far end requires a DH group in phase 2 — it
        # picks AES_CBC_128/HMAC_SHA1_96/MODP_1024 — and the inherited proposal
        # list offered none, which came back as NO_PROPOSAL_CHOSEN. The
        # non-PFS entries stay as a fallback.
        esp=aes256-sha1-modp1024,aes128-sha1-modp1024,3des-sha1-modp1024,aes256-sha1,aes128-sha1,3des-sha1,aes256-sha256,aes128-sha256
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
          secrets_file = /var/lib/secrets/l2tp/ipsec.secrets
        }
      }
    }

    starter {
      config_file = /run/l2tp/ipsec.conf
    }
  '';

  mkIpsecConf = pkgs.writeShellApplication {
    name = "l2tp-ipsec-conf";
    bashOptions = [
      "errexit"
      "nounset"
    ];
    text = ''
      install -d -m 700 /run/l2tp
      ${pkgs.gnused}/bin/sed "s|@PEER@|$(cat /var/lib/secrets/l2tp/peer)|" \
        ${ipsecConfTemplate} > /run/l2tp/ipsec.conf
      chmod 600 /run/l2tp/ipsec.conf
    '';
  };
in
{
  # What VM105 (l2tp-relay) did: dial the remote site over L2TP/IPsec and let the
  # tailnet reach the remote subnet through it, so reaching it needs no
  # VPN client on the laptop.
  #
  # It is safe to run this on the machine that serves everything else, which was
  # checked rather than assumed: pppd here is configured without `defaultroute`,
  # so ppp0 only ever carries the one remote subnet and the house's default
  # route is untouched. An exit node would be a different story, which is why
  # CT106 is not folded in here.
  #
  # Nothing about the remote site is in this repo. The peer address, the PSK, the
  # account and the host the watchdog probes live in /var/lib/secrets/l2tp/;
  # see README.md for the files.
  #
  # This is also the one part CI cannot verify — there is no remote endpoint to
  # dial from a sandboxed VM. Keep the exported VM105 disk image until the tunnel
  # has come up here at least once.

  # strongSwan 6.1.0 turned IKEv1 off by default, and the far end only speaks
  # IKEv1. Without this charon answers every attempt with "IKE version 1 not
  # supported"; a tunnel brought up by 6.0.7 survived the upgrade until the next
  # reboot, which is why it looked fine for days. Drop this when the far end moves
  # to IKEv2 or upstream removes IKEv1 for good.
  nixpkgs.overlays = [
    (_: prev: {
      strongswan = prev.strongswan.overrideAttrs (old: {
        configureFlags = old.configureFlags ++ [ "--enable-ikev1" ];
      });
    })
  ];

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
    serviceConfig.ExecStartPre = [ "+${lib.getExe mkIpsecConf}" ];
  };

  # pppd has its chap-secrets path compiled in, so this one has to be in /etc.
  systemd.tmpfiles.rules = [
    "d /var/lib/secrets/l2tp 0700 root root -"
    "L+ /etc/ppp/chap-secrets - - - - /var/lib/secrets/l2tp/chap-secrets"
  ];

  systemd.services.l2tp-vpn = {
    description = "L2TP/IPsec tunnel (subnet router uplink)";
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
      # Clear whatever the last attempt left behind first. preStop is the usual cleanup, but if
      # it does not run to completion the old IKE SA stays in charon and every later `ipsec up`
      # times out against it — on 2026-10-28 a clobbered /dev/null broke preStop's redirects and
      # the tunnel stayed down for two hours, until a reboot cleared charon.
      ipsec down l2tp || true
      ipsec up l2tp
      sleep 2
      mkdir -p /run/xl2tpd
      xl2tpd -c /var/lib/secrets/l2tp/xl2tpd.conf -D &
      sleep 2
      echo "c l2tp" > /run/xl2tpd/l2tp-control
      sleep 6
      ip -4 addr show ppp0 || echo "ppp0 not up"
      # pppd only gets a host route to the peer, so the remote subnets have to be
      # added here. Both are live: the L2TP pool is 192.168.1.0/24 and the dev
      # machines answer on 10.80.1.0/24 as well.
      ip route replace 192.168.1.0/24 dev ppp0 || true
      ip route replace 10.80.1.0/24 dev ppp0 || true
      ip route | grep ppp0 || echo "no remote route"
    '';
    preStop = ''
      echo "d l2tp" > /run/xl2tpd/l2tp-control 2>/dev/null || true
      sleep 1
      ipsec down l2tp 2>/dev/null || true
    '';
    wantedBy = [ "multi-user.target" ];
  };

  # The tunnel drops without saying so, so something has to notice. Probing a
  # host on the far side rather than the interface, because ppp0 can exist while
  # nothing is reachable through it.
  systemd.services.l2tp-vpn-watchdog = {
    description = "L2TP VPN watchdog";
    path = with pkgs; [
      iproute2
      systemd
      bash
    ];
    serviceConfig.Type = "oneshot";
    # probe-host is host:port. /dev/tcp wants host/port, so the probe could never
    # open and the watchdog tore down a working tunnel every ten minutes — which
    # also dropped ssh into this box on the same schedule. Split it rather than
    # changing the file's format, since that is the form every other host uses.
    script = ''
      target="$(cat /var/lib/secrets/l2tp/probe-host)"
      if ! ip -4 addr show ppp0 >/dev/null 2>&1 \
        || ! timeout 5 bash -c "echo > /dev/tcp/''${target%:*}/''${target##*:}" 2>/dev/null; then
        echo "tunnel down -> reconnecting"
        systemctl restart l2tp-vpn.service
      fi
    '';
  };
  systemd.timers.l2tp-vpn-watchdog = {
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
