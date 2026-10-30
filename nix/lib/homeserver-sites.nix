# The homeserver's vhost table, shared by hosts/homeserver.nix (Caddy vhosts + gatus checks)
# and homelab/homepage.nix (the dashboard's hrefs and siteMonitor URLs), so a port lives in
# exactly one place.
{ pkgs }:
rec {
  # Because Proxmox is replaced in one cut rather than drained service by service,
  # everything that used to sit on CT101 or in the HAOS VM ends up on this host.
  # Only two upstreams stay remote.
  macmini = "100.105.135.49"; # Mac mini AI node, stays where it is

  gatusPort = 8084;
  autheliaPort = 9092; # keep in sync with homelab/authelia.nix

  # One table drives the reverse proxy, the uptime checks and the homepage dashboard. The old setup
  # kept those in two places (Caddyfile + uptime-kuma's GUI) plus a third copy of
  # the Caddyfile in this repo that had already drifted out of sync with the live one.
  sites = {
    home = {
      upstream = "127.0.0.1:8123"; # home assistant, container
      extra = "header_up -X-Forwarded-For";
    };
    # Authelia (auth = true) is applied only to "UIs that hold personal data or expose
    # destructive operations" (policy narrowed on 2026-09-26). View-only things with no stored
    # data (dash / search / status / tools) are left out because reaching the tailnet is
    # enough. Applying it there would only demand a login every time from private windows,
    # the iPhone, and the CLI, with no asset being protected.
    dash = {
      upstream = "127.0.0.1:3000"; # homepage
      monitor = false; # lazy: lazy-http-services.nix reports it to gatus daily
    };
    vault.upstream = "127.0.0.1:8080"; # vaultwarden
    rss.upstream = "127.0.0.1:8081"; # miniflux
    read = {
      upstream = "127.0.0.1:8087"; # readeck (read later)
      monitor = false; # lazy: lazy-http-services.nix reports it to gatus daily
    };
    search.upstream = "127.0.0.1:8088"; # searxng
    obsidian = {
      upstream = "127.0.0.1:5984"; # couchdb (LiveSync)
      # CouchDB uses require_valid_user, so / returns 401. That is the healthy response, and
      # the default `< 400` was always red. The 401 itself is used as the liveness check.
      expect = [ "[STATUS] == 401" ];
    };
    # Sync target for the Firefox extensions (homelab/webdav.nix). Basic auth, so / is 401.
    webdav = {
      upstream = "127.0.0.1:8115";
      expect = [ "[STATUS] == 401" ];
    };
    dav.upstream = "127.0.0.1:5232"; # radicale (homelab/webmail.nix adds InfCloud under /infcloud/)
    # Twake Mail (homelab/webmail.nix). Login is a Stalwart account, so no Authelia in front.
    webmail = {
      upstream = "127.0.0.1:8121";
      interval = "1h";
    };
    # The two for the circle. Like cal, they are published via cloudflared rather than Caddy,
    # so the vhosts here are never hit. They are listed only because gatus monitoring can
    # only be generated from here.
    poll = {
      upstream = "127.0.0.1:8089"; # rallly (scheduling)
      monitor = false; # lazy: lazy-http-services.nix reports it to gatus daily
    };
    split = {
      upstream = "127.0.0.1:8090"; # spliit (bill splitting)
      monitor = false; # lazy: lazy-http-services.nix reports it to gatus daily
    };
    # Unified calendar feed (unified-calendar.nix). Unlike the others, it is published via
    # cloudflared rather than Caddy, so nobody actually hits the vhost generated here. It is
    # listed only because gatus monitoring targets are generated from this table alone.
    ical.upstream = "127.0.0.1:8113";
    # calnode (booking page). Unlike the others, it is published via cloudflared rather than
    # Caddy, so nobody actually hits the vhost generated here — booking.gapul.net is a CNAME
    # to the tunnel. It is still listed because gatus monitoring targets are generated from
    # this table alone. The monitor hits the upstream directly, so it works without the vhost.
    booking.upstream = "127.0.0.1:8086";
    # Zipline (homelab/zipline.nix). Published via cloudflared like booking; listed here for gatus.
    snap.upstream = "127.0.0.1:8114";
    # The DNS record and the dashboard link existed already, but the vhost did not, so opening
    # it over https failed (easy to miss because hitting the port directly worked).
    jellyfin = {
      upstream = "127.0.0.1:8096";
      monitor = false; # lazy: lazy-http-services.nix reports it to gatus daily
    };
    # Location log (Dawarich). It was missing from the table, so there was no vhost and no gatus
    # monitor, and the iPhone sent directly to the raw tailnet address — the kind of setup that
    # silently breaks when a migration changes the address. Note that HTTP responses don't show
    # that uploads stopped (on 2026-08-23 they stopped for 36 hours while the web UI still
    # opened). dawarich-freshness.nix watches for that.
    track.upstream = "127.0.0.1:3005";
    navidrome = {
      upstream = "127.0.0.1:4533";
      monitor = false; # lazy: lazy-http-services.nix reports it to gatus daily
    };
    # 3D printer control panel (Bambuddy). Putting the printer in LAN Only + Developer Mode made
    # Bambu Handy unusable, so this is where the phone goes instead. See homelab/bambuddy.nix.
    bambu.upstream = "127.0.0.1:8010";
    # Household ledger (fava). The ledger, sync jobs, and fava live in homelab/ledger.nix (moved
    # from macmini on 2026-09-23; macmini is not an always-on host). fava itself has no login,
    # so Authelia sits in front of it.
    money = {
      upstream = "127.0.0.1:5075";
      auth = true;
    };
    # Stalwart's JMAP and admin UI (homelab/mail.nix). Stalwart handles auth itself.
    # IMAPS 993 does not go through here; it is exposed on the tailnet directly.
    mail.upstream = "127.0.0.1:8120";
    # Game shelves. roms is RomM (playable directly in the browser); games is Gameyfin
    # (a catalog of DRM-free PC games). The actual files for both live under /srv/games and
    # are excluded from restic — the same treatment as the rest of /srv: don't spend space on
    # things that can be dumped again.
    roms = {
      upstream = "127.0.0.1:8091";
      monitor = false; # lazy: lazy-http-services.nix reports it to gatus daily
    };
    games = {
      upstream = "127.0.0.1:8092";
      monitor = false; # lazy: lazy-http-services.nix reports it to gatus daily
    };
    paperless = {
      upstream = "127.0.0.1:8097";
      monitor = false; # lazy: lazy-http-services.nix reports it to gatus daily
    };
    # Inventory of belongings (Homebox). LLMs call it with an API key.
    box.upstream = "127.0.0.1:8104";
    git.upstream = "127.0.0.1:3003"; # forgejo
    # Signet (homelab/nostr-bunker.nix), the NIP-46 signer for gapul@gapul.net's
    # Nostr key. Behind Authelia: this is a key-management admin panel, not a
    # public page, and the daemon it proxies to has no auth of its own.
    bunker = {
      upstream = "127.0.0.1:4174";
      auth = true;
    };
    archive = {
      upstream = "127.0.0.1:8000"; # archivebox
      auth = true;
      # The REST API is protected by ArchiveBox's own API key (X-ArchiveBox-API-Key).
      # Putting Authelia here turns submissions from the iPhone share sheet into a login page.
      authSkip = "/api/*";
      monitor = false; # lazy: lazy-http-services.nix reports it to gatus daily
    };
    # Meal log (homelab/wger.nix). It has its own login and the official iOS app calls it
    # directly, so no Authelia. Caddy serves the static files.
    food = {
      upstream = "127.0.0.1:8106";
      pre = ''
        handle /static/* {
          root * /var/lib/homelab/wger
          file_server
        }
        handle /media/* {
          root * /var/lib/homelab/wger
          file_server
        }
      '';
    };
    # Audiobooks (homelab/audiobookshelf.nix). The iPhone Audiobookshelf app and Readest's ABS
    # integration call it directly with their own login, so no Authelia in front.
    audiobooks = {
      upstream = "127.0.0.1:8107";
      interval = "1h";
    };
    # E-books (homelab/kavita.nix). Readest reads OPDS via a URL containing an API key.
    books = {
      upstream = "127.0.0.1:8108";
      interval = "1h";
    };
    ntfy.upstream = "127.0.0.1:8082";
    cache.upstream = "127.0.0.1:8083"; # attic (own nix binary cache)
    shell.upstream = "127.0.0.1:8888"; # atuin (shell history sync server)
    # blocky's API/metrics (no UI). /check is a custom single page (configs/homelab/dns-check.html):
    # it lets the phone check a domain and pause blocking for 10 minutes. /mm/ exposes macmini's
    # blocky API on the same origin (macmini is the tailnet's first resolver, so pausing only one
    # of them has no effect, and an https page can't call the plaintext API at 100.x:4000 due
    # to mixed content).
    dns2 = {
      upstream = "127.0.0.1:4000";
      pre = ''
        handle_path /check* {
          root * ${pkgs.writeTextDir "index.html" (builtins.readFile ../../configs/homelab/dns-check.html)}
          file_server
        }
        handle_path /mm/* {
          reverse_proxy ${macmini}:4000
        }
      '';
    };
    # These two used to be reached through Home Assistant's add-on ingress, which
    # does not exist without Supervisor. Both need their own A record in
    # Cloudflare pointing at this host's tailnet address, same as the others.
    esphome = {
      upstream = "127.0.0.1:6052";
      auth = true;
    };
    nodered = {
      upstream = "127.0.0.1:1880";
      auth = true;
    };
    tools.upstream = "${macmini}:8901";
    # RecallVault's iPhone client authenticates with its own bearer token, so this
    # machine endpoint must not be placed behind the browser-oriented Authelia flow.
    # The receiver answers only /health, /v1/status and /v1/watch-chunks; / is always 404.
    recall = {
      upstream = "${macmini}:8766";
      probePath = "/health";
    };
    # Intake for iPhone Health data (homelab/health.nix). A machine endpoint the PulsHealth app
    # calls with a bearer token, so no Authelia in front. / requires auth, so healthy means 401.
    health = {
      upstream = "127.0.0.1:8105";
      expect = [ "[STATUS] == 401" ];
    };
    # T3 Code on macmini (home/macmini.nix). Its web client needs TLS (plain HTTP + a raw IP is not
    # a secure context), and the tailscale serve name does not resolve here: MagicDNS's ts.net split
    # route doesn't take effect in the OS on these devices, so it goes through gapul.net instead.
    # No Authelia on the app itself: the server rejects clients without a paired session.
    t3.upstream = "${macmini}:3773";
    # T3 Code on sean, which binds it to its own loopback. macmini holds
    # the ssh tunnel to it (launchd.agents.t3code-sean-tunnel in home/macmini.nix).
    "t3-sean".upstream = "${macmini}:3775";
    # Its pairing page does mint those sessions, so it sits behind Authelia.
    t3pair = {
      upstream = "${macmini}:3774";
      auth = true;
      probePath = "/health";
    };
    sync = {
      upstream = "127.0.0.1:8384"; # syncthing rejects requests whose Host it doesn't know
      extra = "header_up Host {upstream_hostport}";
    };
    # Filestash replaces File Browser and exposes both the read-only Restic view
    # and the writable Google Drive mount from one tailnet-only UI.
    files = {
      upstream = "127.0.0.1:8099";
      auth = true;
      monitor = false; # lazy: lazy-http-services.nix reports it to gatus daily
    };
    # Public forms keep their own login for administration. Cloudflared sends
    # the public hostname to the same local gateway; this entry also supplies
    # the tailnet vhost and the direct upstream health check.
    forms = {
      upstream = "127.0.0.1:8102";
      monitor = false; # lazy: lazy-http-services.nix reports it to gatus daily
    };
    # Anki sync server. Kept self-hosted rather than on AnkiWeb. Clients are amgi on iOS and
    # the Anki desktop app on the main Mac. The sync protocol is HTTP, so a plain vhost is enough.
    anki = {
      upstream = "127.0.0.1:27701";
      # The sync server serves nothing at the root, so / is 404. It was written expecting an
      # auth-demanding 401, but the real server returned 404 (/sync/meta returns 405 for GET).
      # That 404 itself proves "the HTTP server is up", so it is used as the liveness check.
      expect = [ "[STATUS] == 404" ];
    };
    # pve.gapul.net has nothing left to point at.
    # Replaced uptime-kuma, which kept its monitor list in a SQLite file no one
    # could review. It ran on the Raspberry Pi and was stopped on 2026-08-12 —
    # every target in it still pointed at the CT this host replaced, so it had been
    # red across the board and watching nothing. Its job is the `sites` table now.
    # The SSO login page itself. Putting forward_auth here would make it ask itself for
    # authentication and loop forever, so no auth.
    auth.upstream = "127.0.0.1:${toString autheliaPort}";
    status = {
      upstream = "127.0.0.1:${toString gatusPort}";
      monitor = false; # monitoring the monitor from itself proves nothing
    };
  };
}
