{
  pkgs,
  lib,
  config,
  user,
  ...
}:
let
  # Because Proxmox is replaced in one cut rather than drained service by service,
  # everything that used to sit on CT101 or in the HAOS VM ends up on this host.
  # Only two upstreams stay remote.
  macmini = "100.105.135.49"; # Mac mini AI node, stays where it is

  gatusPort = 8084;

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
    dash.upstream = "127.0.0.1:3000"; # homepage
    vault.upstream = "127.0.0.1:8080"; # vaultwarden
    rss.upstream = "127.0.0.1:8081"; # miniflux
    obsidian = {
      upstream = "127.0.0.1:5984"; # couchdb (LiveSync)
      # CouchDB は require_valid_user なので / は 401 を返す。これが健全な応答で、
      # 既定の `< 400` では常に赤かった。401 が返ること自体を生存確認に使う。
      expect = [ "[STATUS] == 401" ];
    };
    dav.upstream = "127.0.0.1:5232"; # radicale
    # DNS レコードもダッシュボードのリンクも前からあったのに vhost だけ無く、
    # https で開くと繋がらない状態だった (直接ポートを叩けば見えるので気付きにくい)。
    jellyfin.upstream = "127.0.0.1:8096";
    navidrome.upstream = "127.0.0.1:4533";
    paperless.upstream = "127.0.0.1:8097";
    git.upstream = "127.0.0.1:3003"; # forgejo
    archive.upstream = "127.0.0.1:8000"; # archivebox
    ntfy.upstream = "127.0.0.1:8082";
    cache.upstream = "127.0.0.1:8083"; # attic (own nix binary cache)
    dns2.upstream = "127.0.0.1:4000"; # blocky の API/metrics (UI は無い)
    # These two used to be reached through Home Assistant's add-on ingress, which
    # does not exist without Supervisor. Both need their own A record in
    # Cloudflare pointing at this host's tailnet address, same as the others.
    esphome.upstream = "127.0.0.1:6052";
    nodered.upstream = "127.0.0.1:1880";
    comfy.upstream = "${macmini}:8188";
    chat.upstream = "127.0.0.1:3010"; # open-webui
    docs.upstream = "127.0.0.1:3011"; # anythingllm
    tools.upstream = "${macmini}:8901";
    sync = {
      upstream = "127.0.0.1:8384"; # syncthing rejects requests whose Host it doesn't know
      extra = "header_up Host {upstream_hostport}";
    };
    # A read-only window onto the restic repository, rebuilt here from the two
    # hand-written units that ran on the pve host (homelab/restic-view.nix).
    files.upstream = "127.0.0.1:8085";
    # Anki の同期サーバ。AnkiWeb に預けず自前で持つ。クライアントは iOS の amgi と
    # 母艦の Anki 本体。同期プロトコルは HTTP なので普通の vhost で足りる。
    anki = {
      upstream = "127.0.0.1:27701";
      # 同期サーバはルートに何も生やさないので / は 404。認証を要求する 401 だと
      # 思って書いたら実機は 404 だった (/sync/meta は GET だと 405)。この 404 自体が
      # 「HTTP サーバが上がっている」証拠なので、それを生存確認に使う。
      expect = [ "[STATUS] == 404" ];
    };
    # pve.gapul.net has nothing left to point at.
    # Replaced uptime-kuma, which kept its monitor list in a SQLite file no one
    # could review. It ran on the Raspberry Pi and was stopped on 2026-08-12 —
    # every target in it still pointed at the CT this host replaced, so it had been
    # red across the board and watching nothing. Its job is the `sites` table now.
    status = {
      upstream = "127.0.0.1:${toString gatusPort}";
      monitor = false; # monitoring the monitor from itself proves nothing
    };
  };

  # reverse_proxy takes an optional block; only emit braces when there is
  # something to put inside them.
  mkVhost =
    site:
    let
      block = lib.optionalString (site ? extra) " {\n    ${site.extra}\n  }";
    in
    {
      extraConfig = ''
        tls ${certDir}/cert.pem ${certDir}/key.pem
        reverse_proxy ${site.upstream}${block}
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
  # box sits at 6.1GB used with 9.3GB available and the ARC pegged at its ceiling,
  # so it was reading from disk for want of 2GB it had to spare. 4GB still leaves
  # ~5GB of headroom.
  boot.kernelParams = [ "zfs.zfs_arc_max=4294967296" ];
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
    useRoutingFeatures = "server";
    # Connects itself on first boot. The key is placed by hand like the other
    # secrets — the point is that a reinstall does not need someone to remember
    # to run `tailscale up`, which is exactly the step that leaves a headless
    # box unreachable.
    authKeyFile = "/var/lib/secrets/tailscale.key";
    # Two subnets: the house, and the office network reached over the L2TP tunnel
    # in homelab/vpn-relay.nix. The second one used to be advertised by VM105.
    extraUpFlags = [ "--advertise-routes=192.168.116.0/24,192.168.1.0/24,10.80.1.0/24" ];
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
          url = "http://${site.upstream}";
          interval = "2m";
          # Not `== 200`: several of these answer 3xx when perfectly healthy.
          # A service whose healthy answer is 4xx sets `expect` in the table above.
          conditions = site.expect or [ "[STATUS] < 400" ];
          alerts = [ ntfyAlert ];
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
              "[BODY].server.name == Conduit"
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

  # Matter だけは例外で、LAN 側を開けないと成立しない。デバイスの発見が同一 L2 の
  # mDNS なので、5353 が閉じていると commissioning が必ず `Discovery timed out` で
  # 落ちる (2026-08-16 に SESAME Hub 3 で踏んだ。ペアリングコードは正しく、機器も
  # 同じネットワークにいるのに、homeserver からは広告が一件も見えなかった)。
  # 5540 は commissioning 後の運用トラフィック。
  #
  # tailnet 越しには来ないので trustedInterfaces では埋まらない。LAN インターフェイス
  # に限定して開ける。
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
  # Public-key only. Keys are not declared here: they live in the Bitwarden-managed
  # agent, and this repo is public. Add them by hand, or via sops once it is wired.
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

  # Container images. Every stack pins `:latest` but nothing re-pulled it, so the tags had been
  # frozen since the machine was built. `podman auto-update` only touches containers that opt in
  # with io.containers.autoupdate=registry, and rolls a container back if the new image fails to
  # come up, so the opt-in list is deliberately the stateless frontends (see homelab/*.nix).
  systemd.services.homelab-image-update = {
    description = "Pull newer images for containers labelled io.containers.autoupdate";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.podman}/bin/podman auto-update";
    };
  };
  systemd.timers.homelab-image-update = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # After the nightly switch, so a rebuild and an image pull never race.
      OnCalendar = "Sun 05:30";
      Persistent = true;
      RandomizedDelaySec = "30min";
    };
  };

  system.stateVersion = "26.05";
}
