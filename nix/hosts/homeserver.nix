{
  pkgs,
  lib,
  config,
  user,
  ...
}:
let
  # ZFS ARC ceiling in bytes (2GB); see the ZFS section for the history.
  zfsArcMax = 2 * 1024 * 1024 * 1024;
  # Because Proxmox is replaced in one cut rather than drained service by service,
  # everything that used to sit on CT101 or in the HAOS VM ends up on this host.
  # Only two upstreams stay remote.
  macmini = "100.105.135.49"; # Mac mini AI node, stays where it is

  gatusPort = 8084;
  autheliaPort = 9092; # keep in sync with homelab/authelia.nix

  # Wildcard cert issued by security.acme (lego) below. Using one *.gapul.net cert
  # instead of the per-vhost ACME the old Caddyfile did means 1 DNS-01 order rather
  # than 25, and no custom Caddy build with the cloudflare DNS plugin.
  certDir = config.security.acme.certs."gapul.net".directory;

  # One table drives both the reverse proxy and the uptime checks. The old setup
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
      interval = "1h";
    };
    vault.upstream = "127.0.0.1:8080"; # vaultwarden
    rss.upstream = "127.0.0.1:8081"; # miniflux
    read = {
      upstream = "127.0.0.1:8087"; # readeck (read later)
      interval = "1h";
    };
    search.upstream = "127.0.0.1:8088"; # searxng
    obsidian = {
      upstream = "127.0.0.1:5984"; # couchdb (LiveSync)
      # CouchDB uses require_valid_user, so / returns 401. That is the healthy response, and
      # the default `< 400` was always red. The 401 itself is used as the liveness check.
      expect = [ "[STATUS] == 401" ];
    };
    dav.upstream = "127.0.0.1:5232"; # radicale (homelab/webmail.nix adds InfCloud under /infcloud/)
    # Roundcube (homelab/webmail.nix). Login is a Stalwart account, so no Authelia in front.
    webmail = {
      upstream = "127.0.0.1:8121";
      interval = "1h";
    };
    # The two for the circle. Like cal, they are published via cloudflared rather than Caddy,
    # so the vhosts here are never hit. They are listed only because gatus monitoring can
    # only be generated from here.
    poll = {
      upstream = "127.0.0.1:8089"; # rallly (scheduling)
      interval = "1h"; # socket activation: do not keep the container awake
    };
    split = {
      upstream = "127.0.0.1:8090"; # spliit (bill splitting)
      interval = "1h";
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
    i.upstream = "127.0.0.1:8114";
    # The DNS record and the dashboard link existed already, but the vhost did not, so opening
    # it over https failed (easy to miss because hitting the port directly worked).
    jellyfin = {
      upstream = "127.0.0.1:8096";
      interval = "1h";
    };
    # Location log (Dawarich). It was missing from the table, so there was no vhost and no gatus
    # monitor, and the iPhone sent directly to the raw tailnet address — the kind of setup that
    # silently breaks when a migration changes the address. Note that HTTP responses don't show
    # that uploads stopped (on 2026-08-23 they stopped for 36 hours while the web UI still
    # opened). dawarich-freshness.nix watches for that.
    track.upstream = "127.0.0.1:3005";
    navidrome = {
      upstream = "127.0.0.1:4533";
      interval = "1h";
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
      interval = "1h";
    };
    games = {
      upstream = "127.0.0.1:8092";
      interval = "1h";
    };
    paperless = {
      upstream = "127.0.0.1:8097";
      interval = "1h"; # socket activation (lazy-http-services.nix): do not keep the container awake
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
      interval = "1h";
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
    # T3 Code on the work machine mvrx-nolang-dev, which binds it to its own loopback. macmini holds
    # the ssh tunnel to it (launchd.agents.t3code-mvrx-tunnel in home/macmini.nix).
    "t3-mvrx".upstream = "${macmini}:3775";
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
      interval = "1h";
    };
    # Public forms keep their own login for administration. Cloudflared sends
    # the public hostname to the same local gateway; this entry also supplies
    # the tailnet vhost and the direct upstream health check.
    forms = {
      upstream = "127.0.0.1:8102";
      interval = "1h";
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

  # reverse_proxy takes an optional block; only emit braces when there is
  # something to put inside them.
  # SSO. Only vhosts with auth = true consult Authelia before reverse_proxy.
  # If not logged in, Authelia sends a 302 to the login page; on return, Remote-* headers are
  # passed upstream (if the receiving side supports them, that identifies the user).
  #
  # The target is chosen per entry because this table mixes browser UIs with endpoints that
  # machines call. Applying it across the board would silently break iPhone location logging
  # (track), Obsidian sync (obsidian), the build cache (cache), and notifications (ntfy).
  # Services with their own login (jellyfin/navidrome/git/paperless/rss/roms/games) are also
  # left out. Native apps and git call them directly, so putting a human-facing login page in
  # front breaks the apps. vault is left out for a different reason
  # (putting the password vault behind SSO means it can't be opened if the SSO password is forgotten).
  # With an empty matcher it applies to all requests; if given, to everything except those paths.
  # The exclusion exists for "paths that machines call with an API key" (archive's /api/*).
  # Human-facing pages still get Authelia as before.
  mkForwardAuth =
    skip:
    let
      matcher = lib.optionalString (skip != null) "@protected not path ${skip}\n    ";
      target = lib.optionalString (skip != null) "@protected ";
    in
    ''
      ${matcher}forward_auth ${target}127.0.0.1:${toString autheliaPort} {
        uri /api/authz/forward-auth
        copy_headers Remote-User Remote-Groups Remote-Name Remote-Email
      }
    '';

  mkVhost =
    site:
    let
      block = lib.optionalString (site ? extra) " {\n    ${site.extra}\n  }";
      auth = lib.optionalString (site.auth or false) (mkForwardAuth (site.authSkip or null));
      # Raw Caddy directives placed before the proxy, for a vhost that also serves
      # something else (a static page, a second upstream on a path prefix).
      pre = site.pre or "";
    in
    {
      extraConfig = ''
        tls ${certDir}/cert.pem ${certDir}/key.pem
        ${pre}
        ${auth}reverse_proxy ${site.upstream}${block}
      '';
    };
in
{
  # Home server, replacing the single-node Proxmox install (pve, 192.168.116.100)
  # outright: no hypervisor, so the four LXC containers and the HAOS/VPN VMs all
  # become services or podman containers on this host.
  #
  # The swap is direct rather than staged through a NixOS VM on the old Proxmox,
  # which means there is no per-service rollback: everything has to be declared and
  # verified *before* pve is wiped. Consequences of that choice:
  #   - verification happens in a NixOS VM test in CI, not on the live box
  #   - the whole disk is declared (hosts/homeserver-disk.nix) since install day
  #     needs it, and ZFS replaces vzdump's per-guest snapshots
  #   - the 35GB of service data (CT101's 23GB, HAOS's 9.2GB, matter's 8MB) must be
  #     copied off the box first; the 200GB mount is on the same NVMe and does not count
  #
  # Everything the old box ran is declared: CT101's stacks, the HAOS VM, the four
  # LXC containers and VM105's office tunnel. The one thing not carried over is
  # CT106, and only because there was nothing in it — the mullvad and wg binaries
  # are installed but /etc/wireguard is empty and its default route is the plain
  # LAN one, so it has been a tailscale node doing nothing. If a Mullvad exit node
  # is wanted, it is a fresh build, and it wants its own netns rather than this
  # host's routing table.
  imports = [
    ./homeserver-hardware.nix
    ../modules/authorized-keys.nix
    ../homelab # the Docker stacks that used to live on CT101 under dockge
  ];

  # --- Boot ---
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # Generations are the rollback that Proxmox never had. Keep a decent number of
  # them; the ESP is 1GB and dedicated.
  boot.loader.systemd-boot.configurationLimit = 10;

  # No swap partition; compressed RAM instead. The box it replaces was swapping
  # (CT101 had used 511MB of its 512MB) purely because a 4GB VM sat next to it.
  zramSwap.enable = true;

  # --- ZFS ---
  # Required by the pool import; any stable 8 hex digits will do, it just has to
  # differ between machines sharing a pool (nothing here does).
  networking.hostId = "8f3a1c02";
  # Don't import a pool another host may still hold. This is also where nixpkgs is
  # heading — it becomes the default in 26.11 — so it stays.
  #
  # It did make the first install unbootable, but the setting was not the bug: the
  # installer still had the pool imported when the machine rebooted, so the pool
  # carried the installer's hostid and the new system correctly refused it. The
  # fix is to export the pool before leaving the installer, which the runbook now
  # says to do. Forcing the import would have papered over that.
  boot.zfs.forceImportRoot = false;

  # What actually made it unrecoverable: the refusal drops to an initrd emergency
  # shell, and that shell would not open because root has no password. No console
  # access, no ssh, nothing — recovery needed a USB stick. A machine that can
  # refuse to import must also let someone in to resolve it.
  boot.initrd.systemd.emergencyAccess = true;
  # ARC defaults to half of RAM, which would quietly eat the ~4.7GB this migration
  # is meant to recover. 2GB was the starting point; with everything moved in, the
  # box sat at 6.1GB used with 9.3GB available and the ARC pegged at its ceiling,
  # so it went to 4GB. Since then the Matrix bridges (14 of them), Stalwart and
  # Dawarich moved in: 2026-09-30 the box was at 11.2GB used, 4.5GB available and
  # 4.2GB of the zram swap in use, with the ARC still pegged at 4GB. Back to 2GB:
  # a cache is the one thing here that can shrink without breaking anything.
  #
  # The kernel parameter only applies at boot, so the oneshot below writes the
  # same value to sysfs and a switch takes effect without a reboot. Keep the two
  # in step.
  boot.kernelParams = [ "zfs.zfs_arc_max=${toString zfsArcMax}" ];
  systemd.services.zfs-arc-max = {
    description = "Apply zfs_arc_max without a reboot";
    wantedBy = [ "multi-user.target" ];
    after = [ "zfs-import.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/sh -c 'echo ${toString zfsArcMax} > /sys/module/zfs/parameters/zfs_arc_max'";
    };
  };
  services.zfs.autoScrub.enable = true;
  services.zfs.trim.enable = true;
  # The actual replacement for vzdump's nightly per-guest snapshots. Dataset
  # properties in hosts/homeserver-disk.nix decide what is included (/nix is not).
  services.zfs.autoSnapshot.enable = true;

  networking.hostName = "homeserver";
  networking.useDHCP = lib.mkDefault true;
  # 192.168.116.98 is a reservation, so DHCP stays on — but not on the container
  # side. podman makes a veth per container, dhcpcd solicits a lease on each one,
  # and every container restart takes udevd and tailscaled around the loop with it.
  # With ~24 veths that is a permanent background load for addresses nothing wants.
  networking.dhcpcd.denyInterfaces = [
    "veth*"
    "podman*"
    "br-*"
  ];
  # Already the default, stated because something depends on it: Matter requires
  # IPv6 even for Wi-Fi devices, and turning this off would leave every Matter
  # device unavailable while the server itself looks healthy.
  networking.enableIPv6 = true;

  # Carried over from the pve host, which had powertop's autotune enabled. Idle
  # power on a box that runs 24/7 is worth the tuning.
  powerManagement.powertop.enable = true;

  time.timeZone = "Asia/Tokyo";
  i18n.defaultLocale = "ja_JP.UTF-8";

  # --- Tailscale ---
  # Subnet router, taking over from CT102. Advertising the same route from two nodes
  # is safe (tailscale picks one as primary), so this can be enabled before CT102 is
  # switched off, and the old one is the fallback while cutting over.
  #
  # The office subnet is reachable because of homelab/vpn-relay.nix; advertising it
  # while the tunnel is down simply means those packets go nowhere, same as before.
  #
  services.tailscale = {
    enable = true;
    # This used to be pulled from unstable here (the 26.05 series was stuck at 1.98.10 while
    # upstream was at 1.102.3). No longer needed since nixpkgs-nixos moved to nixos-unstable on 2026-08-31.
    useRoutingFeatures = "server";
    # Connects itself on first boot. The key is placed by hand like the other
    # secrets — the point is that a reinstall does not need someone to remember
    # to run `tailscale up`, which is exactly the step that leaves a headless
    # box unreachable.
    authKeyFile = "/var/lib/secrets/tailscale.key";
    # The house; the office network reached over the L2TP tunnel in
    # homelab/vpn-relay.nix (once advertised by VM105); and UTNET over
    # homelab/utokyo-vpn.nix. These flags only apply when the node first logs in —
    # on a running box change the routes with `tailscale set --advertise-routes=...`.
    extraUpFlags = [
      "--advertise-routes=192.168.116.0/24,192.168.1.0/24,10.80.1.0/24,130.69.0.0/16,133.11.0.0/16,157.82.0.0/16,192.51.208.0/20"
    ];
  };

  # --- TLS ---
  # DNS-01 against Cloudflare, because every name here resolves to a tailnet address
  # and no port 80 is reachable from the internet for HTTP-01.
  #
  # The credential is a plain env file placed by hand at first: sops-nix can only
  # encrypt to this host's age key, and that key does not exist until the host does.
  # Move it under secrets/secrets.yaml once the host is up.
  #   /var/lib/secrets/acme-cloudflare.env  (mode 0400, root)
  #   CF_DNS_API_TOKEN=...
  # Note the name: lego wants CF_DNS_API_TOKEN, while the Caddy plugin this replaces
  # read CF_API_TOKEN from /etc/caddy/cf.env. Same token, different variable.
  security.acme = {
    acceptTerms = true;
    # A GitHub noreply address, since this repo is public (the real one lives in
    # secrets.yaml). Expiry mail therefore bounces; renewal is automatic and its
    # failure shows up as every vhost going red in gatus.
    defaults.email = user.gitEmail;
    certs."gapul.net" = {
      domain = "*.gapul.net";
      dnsProvider = "cloudflare";
      environmentFile = "/var/lib/secrets/acme-cloudflare.env";
      # Let caddy read the key without running as root.
      group = "caddy";
      # Caddy loads `tls <cert> <key>` files once and caches them, so without this
      # every vhost would serve the expired cert ~90 days after install.
      reloadServices = [ "caddy.service" ];
    };
  };

  # --- Reverse proxy ---
  services.caddy = {
    enable = true;
    virtualHosts = lib.mapAttrs' (
      name: site: lib.nameValuePair "${name}.gapul.net" (mkVhost site)
    ) sites;
  };

  # Because the vhosts point `tls` at files on disk rather than using an
  # integration that knows about ACME, nothing otherwise stops caddy from starting
  # before those files exist. security.acme's preliminary self-signed cert covers
  # the very first boot, but ordering is what keeps a restart from racing a renewal.
  systemd.services.caddy = {
    after = [ "acme-finished-gapul.net.target" ];
    wants = [ "acme-finished-gapul.net.target" ];
  };

  # --- Uptime ---
  # Probes the upstream directly rather than https://<name>.gapul.net, so the checks
  # are meaningful before DNS points at this host and do not depend on the cert.
  # Caddy's own health is still visible: status.gapul.net is served through it.
  services.gatus = {
    enable = true;
    # The publish URL's topic and its bearer token, same pair restic already uses.
    # gatus substitutes ${VAR} in its own config, so nothing secret is in nix.
    environmentFile = "/var/lib/secrets/gatus.env";
    settings = {
      web.port = gatusPort;
      storage = {
        type = "sqlite";
        path = "/var/lib/gatus/data.db";
      };
      endpoints =
        let
          ntfyAlert = {
            type = "ntfy";
            # Three consecutive failures, so a container restarting during an
            # image update does not page. At a 2m interval that is ~6 minutes.
            failure-threshold = 3;
            send-on-resolved = true;
            enabled = true;
          };
        in
        lib.mapAttrsToList (name: site: {
          inherit name;
          group = "homelab";
          url =
            (if lib.hasPrefix "https://" site.upstream then site.upstream else "http://${site.upstream}")
            + (site.probePath or "");
          interval = site.interval or "2m";
          # Not `== 200`: several of these answer 3xx when perfectly healthy.
          # A service whose healthy answer is 4xx sets `expect` in the table above.
          conditions = site.expect or [ "[STATUS] < 400" ];
          alerts = [ (ntfyAlert // { failure-threshold = site.failureThreshold or 3; }) ];
        }) (lib.filterAttrs (_: site: site.monitor or true) sites)
        # Everything above is dialled on loopback, which says nothing about the
        # path the outside world takes. These three do not come in through this
        # host's Caddy at all — they arrive over a Cloudflare tunnel that runs on
        # the Pi, whose ingress is configured on Cloudflare's side and therefore
        # not in this repo. It kept pointing at the CT this machine replaced, so
        # Matrix federation was down for a day and nothing here noticed.
        #
        # Resolved by real DNS on purpose: the point is to exercise the whole
        # chain, not to confirm the local port is open.
        ++ [
          {
            name = "matrix-federation";
            group = "public";
            url = "https://matrix.gapul.net/_matrix/federation/v1/version";
            interval = "5m";
            conditions = [
              "[STATUS] == 200"
              "[BODY].server.name == Synapse"
            ];
            alerts = [ ntfyAlert ];
          }
          {
            # Presenta runs on the macmini behind its own tunnel. /api/health answers 200 only
            # when the app can reach its Postgres, so this covers the app, the DB and the tunnel.
            name = "presenta";
            group = "public";
            url = "https://presenta.mugen404.com/api/health";
            interval = "5m";
            conditions = [
              "[STATUS] == 200"
              "[BODY].ok == true"
            ];
            alerts = [ ntfyAlert ];
          }
          {
            name = "push-ntfy";
            group = "public";
            url = "https://push.gapul.net/";
            interval = "5m";
            conditions = [ "[STATUS] < 400" ];
            alerts = [ ntfyAlert ];
          }
          {
            name = "cache-attic";
            group = "public";
            url = "https://cache.gapul.net/dotfiles/nix-cache-info";
            interval = "5m";
            # The cache is public, so this needs no token. Checking the body as
            # well because a 200 from Cloudflare's error page would pass on
            # status alone.
            conditions = [
              "[STATUS] == 200"
              "[BODY] == pat(*StoreDir*)"
            ];
            alerts = [ ntfyAlert ];
          }
        ];
      alerting.ntfy = {
        # ntfy runs on this host, so this notifies about everything except ntfy
        # and the machine itself being down. The Pi is the second pair of eyes
        # for that, the same way it is for DNS.
        url = "http://127.0.0.1:8082";
        topic = "\${NTFY_TOPIC}";
        token = "\${NTFY_TOKEN}";
        priority = 3;
      };
    };
  };

  # --- Firewall ---
  # Every *.gapul.net name resolves to this machine's tailnet address, so 80/443
  # only ever arrive over tailscale0 and nothing needs publishing on the LAN.
  #
  # This is narrower than what it replaces, and deliberately so: docker on the old
  # host published every container port on the LAN bridge, whether or not anything
  # used it. Only DNS is opened back up (adguardhome.nix), because clients point at
  # it directly. If some device that is not on the tailnet turns out to talk to
  # Jellyfin (8096), SMB (139/445) or MQTT (1883), open that port here rather than
  # widening the whole thing.
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # Matter is the one exception: it cannot work without opening the LAN side. Device discovery
  # is mDNS on the same L2, so with 5353 closed, commissioning always fails with
  # `Discovery timed out` (hit on 2026-08-16 with a SESAME Hub 3: the pairing code was correct
  # and the device was on the same network, yet homeserver saw not a single advertisement).
  # 5540 is the operational traffic after commissioning.
  #
  # It doesn't arrive over the tailnet, so trustedInterfaces doesn't cover it. Open it only
  # on the LAN interface.
  networking.firewall.interfaces.enp2s0.allowedUDPPorts = [
    5353
    5540
  ];

  # --- Containers ---
  # podman rather than docker: no daemon, and conmon costs ~1-2MB per container
  # where the containerd-shim it replaces measured ~13MB across 34 containers.
  # oci-containers land here as CT101's compose stacks are converted.
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };
  virtualisation.oci-containers.backend = "podman";

  # Docker Hub rate-limits anonymous pulls per IP, and this house reaches that
  # limit easily — the workaround on the old host was to pull through mirror.gcr.io
  # by hand and retag. Install day pulls around thirty images at once into an empty
  # store, which would hit it immediately, so make the mirror the default instead
  # of a manual step.
  environment.etc."containers/registries.conf.d/10-docker-mirror.conf".text = ''
    [[registry]]
    prefix = "docker.io"
    location = "docker.io"

    [[registry.mirror]]
    location = "mirror.gcr.io"
  '';

  # --- Nix ---
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
    # Keep build-time inputs of live outputs across the weekly GC, so the x86_64-linux
    # pr-gate on the runner here does not refetch and rebuild everything afterwards
    # (same reason as darwin-common.nix).
    keep-outputs = true;
    # Same safeguard as the laptop: give up on an unreachable cache quickly and
    # fall through to building from source.
    connect-timeout = 5;
    fallback = true;
    # cache.gapul.net is deliberately absent. attic runs on this host, so pointing
    # this host's builds at it would be circular.
    substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://gapul-dotfiles.cachix.org"
    ];
    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "gapul-dotfiles.cachix.org-1:tGNGJ7SGHrLAjswSIz673st0AepuNjQombMJO0VUq98="
    ];
  };
  programs.nh = {
    enable = true;
    flake = "/home/${user.username}/.dotfiles/nix";
  };

  # --- Access ---
  # Public-key only. The keys themselves are declared in modules/authorized-keys.nix, imported
  # above — this host no longer needs anything placed by hand.
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;

  users.users.${user.username} = {
    isNormalUser = true;
    description = user.username;
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
  };
  programs.zsh.enable = true;

  # home-manager is not wired in yet. roles.linuxServer covers this shape as a
  # standalone home-manager config; folding it into the system config can wait
  # until the services are moved.

  # Pull the merged declaration in every night. The weekly flake.lock PR auto-merges once CI is
  # green, so without this the box would just sit on whatever generation was last switched by hand.
  #
  # `--refresh` is not optional: nix caches `github:` flake references, and a switch run right
  # after a merge will happily rebuild the *previous* revision — that is how two containers got
  # removed on 2026-08-12. A failed build leaves the running generation alone.
  system.autoUpgrade = {
    enable = true;
    flake = "github:gapul/dotfiles?dir=nix#homeserver";
    flags = [ "--refresh" ];
    dates = "04:00";
    randomizedDelaySec = "30min";
    # No reboots: nothing here needs a new kernel badly enough to drop the tunnels at 4am.
    allowReboot = false;
  };

  system.stateVersion = "26.05";
}
