{ lib, pkgs, ... }:
let
  # Policy-routing table for this box's own traffic, and the fwmark WireGuard puts
  # on its encapsulated packets so they skip that table and leave over the LAN.
  # Distinct from the 51820 used inside the mullvad-exit container, and clear of
  # Tailscale's 0xff0000 mark bits.
  table = 51821;
  ip = "${pkgs.iproute2}/bin/ip";
  wg = "${pkgs.wireguard-tools}/bin/wg";
  l2tpPeer = "/var/lib/secrets/l2tp/peer";

  # Services that keep the plain line, by cgroup: everything they start inherits it.
  # - mail: Google sign-ins with an app password from a VPN address are what gets an
  #   account locked, and imapsync timed out against imap.gmail.com once already
  #   (2026-10-30 23:41). Stalwart relays outgoing mail through smtp.gmail.com.
  # - utokyo-vpn: an unattended SSO sign-in (Playwright) plus the ASA session; the
  #   tunnel itself already carries UTNET only.
  # - the Matrix bridges: each is a session signed in as the user, so the far end
  #   knows who it is anyway and Mullvad hides nothing; what it does do is look
  #   like a new location. X rejected the bridge's polling with 404 from the
  #   first Mullvad address on (2026-10-30 19:44), and Meta, LinkedIn and Discord
  #   are the services most quick to checkpoint a login that moves.
  # - searx: Mullvad unblocked none of the engines that refuse the home address
  #   (openverse, unsplash, brave still fail), and the 110-220 ms it adds per
  #   round trip pushed DuckDuckGo, Yandex, Flickr, Pexels and others past the
  #   1.5 s request_timeout, so pages came back half empty (2026-10-31).
  # No dash: systemd reads one as nesting, and "mullvad-bypass.slice" lives at
  # mullvad.slice/mullvad-bypass.slice, which the cgroup match then failed to find.
  bypassSlice = "novpn.slice";
  bypassUnits = [
    "mail-mirror"
    "mail-push-gmail"
    "mail-push-school"
    "mail-push-sean"
    "stalwart"
    "utokyo-vpn"
    "matrix-line"
    "mautrix-bluesky"
    "mautrix-discord"
    "mautrix-gmessages"
    "mautrix-googlechat"
    "mautrix-linkedin"
    "mautrix-meta-instagram"
    "mautrix-meta-messenger"
    "mautrix-signal"
    "mautrix-slack"
    "mautrix-telegram"
    "mautrix-twitter"
    "mautrix-whatsapp"
    "searx"
  ];

  # Rule preferences sit after Tailscale's (5210-5270), so tailscaled's own packets
  # (fwmark 0x80000 -> main at 5210) still go straight out and keep direct
  # connections, and tailnet addresses still resolve through its table 52.
  rules = [
    # Anything main has a more specific route for: the LAN, the container veth,
    # podman bridges, ppp0 (L2TP), utvpn (UTNET).
    "pref 5300 lookup main suppress_prefixlength 0"
    # Everything else, except WireGuard's own encapsulated packets.
    "pref 5310 not fwmark ${toString table} lookup ${toString table}"
  ];
  v4Rules = [
    # The mullvad-exit container already tunnels to Mullvad itself; don't wrap it twice.
    "pref 5290 from 10.233.0.0/24 lookup main"
  ]
  ++ map (r: "${r} lookup main") cloudflareEdge.v4;
  v6Rules = map (r: "${r} lookup main") cloudflareEdge.v6;
  # cloudflared's edge (region1/region2.v2.argotunnel.com, port 7844). Through
  # Mullvad neither QUIC nor TCP reached it (2026-10-30: "Allow outbound QUIC
  # traffic on port 7844", matrix.gapul.net answered 530), so the tunnel that
  # carries every public hostname stays on the plain line. Cloudflare sees the
  # house's address either way: it terminates these hostnames.
  cloudflareEdge = {
    v4 = [
      "pref 5292 to 198.41.192.0/24"
      "pref 5293 to 198.41.200.0/24"
    ];
    v6 = [
      "pref 5292 to 2606:4700:a0::/44"
      "pref 5293 to 2606:4700:a8::/44"
    ];
  };
in
{
  # The homeserver's own outbound traffic goes through Mullvad (a separate device
  # from the mullvad-exit container's). Inbound needs nothing: everything public
  # arrives through outbound tunnels (cloudflared, playit) or the tailnet.
  #
  # Connections already open when the routes change keep their LAN source address
  # and hang once their packets go into the tunnel. After the first switch,
  # blocky and cloudflared had to be restarted; do the same after changing the rules.
  #
  # Not a kill switch: if this interface is down, its table is empty and traffic
  # falls back to the plain LAN route. A box that also deploys itself and is
  # reached remotely should not lose its network because a VPN relay is down.
  #
  # The device is registered on the Mullvad account (devices API); if the account
  # lapses the key is deleted with it and must be registered again, and the
  # addresses below replaced with the ones Mullvad returns.
  networking.wg-quick.interfaces.mullvad = {
    address = [
      "10.131.152.193/32"
      "fc00:bbbb:bbbb:bb01:d:0:3:98c1/128"
    ];
    privateKeyFile = "/var/lib/secrets/mullvad-host.key";
    table = toString table;
    peers = [
      {
        # jp-tyo-wg-201; the container uses jp-tyo-wg-001.
        publicKey = "5YlME8hOnWqvZ7iSampvPW5bG/dJ+PYpaBFV5kfp9UA=";
        endpoint = "146.70.201.2:51820";
        allowedIPs = [
          "0.0.0.0/0"
          "::/0"
        ];
        persistentKeepalive = 25;
      }
    ];
    postUp = ''
      ${wg} set mullvad fwmark ${toString table}
      ${builtins.concatStringsSep "\n" (
        map (r: "${ip} -4 rule add ${r}\n${ip} -6 rule add ${r}") rules
        ++ map (r: "${ip} -4 rule add ${r}") v4Rules
        ++ map (r: "${ip} -6 rule add ${r}") v6Rules
      )}
      # The L2TP/IPsec peer (vpn-relay.nix) stays on the plain line: the far end
      # knows this house by its address. The peer is only known at runtime.
      if [ -s ${l2tpPeer} ]; then
        ${ip} -4 rule add pref 5291 to "$(cat ${l2tpPeer})" lookup main
      fi
    '';
    preDown = ''
      ${builtins.concatStringsSep "\n" (
        map (r: "${ip} -4 rule del ${r} || true\n${ip} -6 rule del ${r} || true") rules
        ++ map (r: "${ip} -4 rule del ${r} || true") v4Rules
        ++ map (r: "${ip} -6 rule del ${r} || true") v6Rules
      )}
      ${ip} -4 rule del pref 5291 || true
    '';
  };

  # The cgroup match is resolved when the rule is inserted, so it can only name a
  # cgroup that exists then. A unit's own cgroup disappears whenever it is stopped
  # (mail-mirror is a timer), so the units go into a slice that is kept up.
  systemd.slices.novpn = {
    description = "Services that bypass the Mullvad tunnel";
    wantedBy = [ "multi-user.target" ];
  };
  systemd.services =
    lib.genAttrs bypassUnits (_: {
      serviceConfig.Slice = bypassSlice;
    })
    // {
      firewall = {
        wants = [ bypassSlice ];
        after = [ bypassSlice ];
      };
    };

  # Marked packets skip the `not fwmark` rule and leave by main. Their source
  # address was already picked from the Mullvad route, so rewrite it on the way out.
  networking.firewall.extraCommands = ''
    ip46tables -t mangle -N mullvad-bypass 2>/dev/null || ip46tables -t mangle -F mullvad-bypass
    ip46tables -t mangle -A mullvad-bypass -m cgroup --path ${bypassSlice} -j MARK --set-mark ${toString table}
    ip46tables -t mangle -C OUTPUT -j mullvad-bypass 2>/dev/null || ip46tables -t mangle -I OUTPUT 1 -j mullvad-bypass
    ip46tables -t nat -C POSTROUTING -o enp2s0 -m mark --mark ${toString table} -j MASQUERADE 2>/dev/null \
      || ip46tables -t nat -A POSTROUTING -o enp2s0 -m mark --mark ${toString table} -j MASQUERADE
  '';
  networking.firewall.extraStopCommands = ''
    ip46tables -t mangle -D OUTPUT -j mullvad-bypass 2>/dev/null || true
    ip46tables -t nat -D POSTROUTING -o enp2s0 -m mark --mark ${toString table} -j MASQUERADE 2>/dev/null || true
  '';
}
