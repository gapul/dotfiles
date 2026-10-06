# Cloudflare tunnel. The entry point that lets gapul.net's three hostnames in from outside;
# it ran in docker on the Raspberry Pi until 2026-08-12.
#
# Why it moved here: every destination is a service inside this box, so putting it on another box
# allows a failure mode where "homeserver is alive but only the tunnel points at the old IP".
# That actually took Matrix federation down for a day. The tunnel going down when homeserver goes
# down is no loss, since whatever it fronts is down at the same time.
#
# The tunnel was recreated. The original homelab-pi was "remotely managed" with its ingress held on
# the Cloudflare side, and cloudflared fetches that at startup and discards the local config
# (measured: the alert destination written locally was ignored and it kept holding http://ntfy:80,
# which only resolves inside the Pi's docker). The API couldn't change config_src after the fact,
# so a new tunnel was made with config_src=local and the CNAMEs swapped. That lets the ingress below
# take effect as is.
#
# Credentials are in /var/lib/secrets/cloudflared-homeserver.json: the three fields {AccountTag,
# TunnelID, TunnelSecret}, which can be reassembled by base64-decoding the tunnel token.
{
  services.cloudflared = {
    enable = true;
    tunnels."3e0ea569-07c5-4d37-a18f-e7295083ed83" = {
      credentialsFile = "/var/lib/secrets/cloudflared-homeserver.json";
      ingress = {
        # Synapse. Federation goes through here only (moved from Conduit 6167 on 2026-08-31).
        "matrix.gapul.net" = "http://127.0.0.1:8008";
        # matrix-hookshot's generic webhooks. Public so that senders outside the
        # tailnet (Cloudflare Email Workers, CI) can post (matrix-hookshot.nix).
        "hooks.gapul.net" = "http://127.0.0.1:9000";
        # ntfy. push is for app notifications; alert is where the unified-calendar worker posts to the
        # watchdog topic. The users and tokens that were on the Pi's ntfy have been moved to this box's
        # ntfy.
        "push.gapul.net" = "http://127.0.0.1:8082";
        "alert.gapul.net" = "http://127.0.0.1:8082";
        # Booking page. This one is pointless unless people outside the tailnet can open it, so unlike
        # the other gapul.net names it goes through the tunnel instead of Caddy. That means
        # booking.gapul.net's DNS is this tunnel's CNAME, not an A record pointing at this box's
        # tailnet address.
        #
        # It used to be cal.gapul.net. That name is claimed as a custom domain by the unified-calendar
        # Worker, which installs a Cloudflare-managed read-only record (AAAA 100::), so this declaration
        # never once took effect even though it was written.
        "booking.gapul.net" = "http://127.0.0.1:8086";
        # Scheduling polls and bill splitting. Both assume handing URLs to the circle and friends, so
        # they go through the tunnel for the same reason as booking. DNS must be this tunnel's CNAME.
        "poll.gapul.net" = "http://127.0.0.1:8089";
        "split.gapul.net" = "http://127.0.0.1:8090";
        # Unified calendar feed (unified-calendar.nix). Phones subscribe over mobile data, so it goes
        # through the tunnel for the same reason as booking. The secret is protected by the feed token,
        # not by the path (URL) (see SPEC.md).
        "ical.gapul.net" = "http://127.0.0.1:8113";
        # File sharing and location sharing. Both assume "the person you send the link to is outside the
        # tailnet", so they go through the tunnel for the same reason as the three above.
        "send.gapul.net" = "http://127.0.0.1:8094";
        # Google Forms replacement. A local Caddy gateway splits the single
        # public origin between Formera's frontend and REST API.
        "forms.gapul.net" = "http://127.0.0.1:8102";
        "where.gapul.net" = "http://127.0.0.1:8095";
        # Screenshot sharing (zipline.nix). Same reason as send: the link goes to people outside
        # the tailnet.
        "snap.gapul.net" = "http://127.0.0.1:8114";
        # Home for my own posts (homelab/social.nix). Fediverse and Nostr only work if external servers
        # and apps can reach them, so all of these go through the tunnel.
        "social.gapul.net" = "http://127.0.0.1:8110";
        "blog.gapul.net" = "http://127.0.0.1:8111";
        "relay.gapul.net" = "http://127.0.0.1:8112";
        # Forgejo (forgejo.nix). Was left on a tailnet-IP A record from the Proxmox migration,
        # which only ever worked for devices on the tailnet; moved through the tunnel like
        # everything else here so it's actually reachable from outside.
        "git.gapul.net" = "http://127.0.0.1:3003";
      };
      # Unknown hostnames get 404. The Pi's config did the same.
      default = "http_status:404";
    };
  };
}
