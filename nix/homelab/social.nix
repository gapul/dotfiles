# Home for public-facing publishing on our own domain. Only lightweight things were picked
# (a few hundred MB of memory in total).
#
#   social.gapul.net  GoToSocial      the Fediverse account @gapul@gapul.net itself
#   relay.gapul.net   nostr-rs-relay  personal relay that always keeps our Nostr posts (writes only from our key)
#   blog.gapul.net    WriteFreely     long-form blog followable from the Fediverse (single user)
#
# All three are pointless unless people outside the tailnet can reach them, so they're exposed
# through the cloudflared tunnel rather than Caddy (homelab/cloudflared.nix). The home IP isn't exposed.
#
# The account is @gapul@gapul.net (account-domain = gapul.net). GoToSocial itself lives at
# social.gapul.net; webfinger / host-meta / nodeinfo at the gapul.net root are routed to
# social.gapul.net by the _redirects of the CF Pages portfolio (gapul/gapul.net). gapul.net's MX
# is left alone. host and account-domain are baked into the DB on first start; changing them
# later means starting over.
#
# Nostr key (NIP-05 is gapul.net/.well-known/nostr.json), rotated to a vanity npub before real use began:
#   npub1gapulzvd6qtpf28gffvnrm5evxp6ca97ygcndgzyd4f7cuux7hzs0p3w6c
# The private key exists only in /var/lib/secrets/nostr.env and is used by the posting endpoint.
_:

let
  nostrPubkeyHex = "4743cf898dd01614a8e84a5931ee996183ac74be223136a0446d53ec7386f5c5";
in
{
  services.gotosocial = {
    enable = true;
    settings = {
      host = "social.gapul.net";
      account-domain = "gapul.net";
      protocol = "https";
      bind-address = "127.0.0.1";
      port = 8110;
      # cloudflared connects from inside the same box, so trust only loopback as the forwarder.
      trusted-proxies = [ "127.0.0.1/32" ];
      letsencrypt-enabled = false;
      accounts-registration-open = false;
      landing-page-user = "gapul";
      instance-languages = [
        "ja"
        "en"
      ];
      # Keep the cache of other servers' images etc. short. Attachments on our own posts aren't removed.
      media-remote-cache-duration = "168h";
    };
  };

  services.nostr-rs-relay = {
    enable = true;
    port = 8112;
    settings = {
      info = {
        relay_url = "wss://relay.gapul.net/";
        name = "gapul";
        description = "gapul's personal relay. Only accepts events from its owner.";
        pubkey = nostrPubkeyHex;
      };
      network = {
        address = "127.0.0.1";
        # Via the tunnel the client looks like 127.0.0.1. This makes rate limiting use the real IP.
        remote_ip_header = "cf-connecting-ip";
      };
      # Not a free public relay. Only our key can write. Anyone may read.
      authorization.pubkey_whitelist = [ nostrPubkeyHex ];
      limits.messages_per_sec = 5;
    };
  };

  services.writefreely = {
    enable = true;
    host = "blog.gapul.net";
    settings = {
      app = {
        host = "https://blog.gapul.net";
        site_name = "gapul";
        single_user = true;
        federation = true;
        public_stats = false;
        open_registration = false;
      };
      server = {
        bind = "127.0.0.1";
        port = 8111;
      };
    };
    # Initial password for the first admin user. The default is "nixos" sitting in the store, so always replace it.
    # Only read the first time (when there are 0 users). Change it in the UI after logging in.
    admin = {
      name = "gapul";
      initialPasswordFile = "/var/lib/secrets/writefreely-admin.password";
    };
  };
}
