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
  # The vhost table (sites) and the ports it shares with this file live in
  # lib/homeserver-sites.nix, which homelab/homepage.nix reads too.
  inherit (import ../lib/homeserver-sites.nix { inherit pkgs; })
    gatusPort
    autheliaPort
    sites
    ;

  # Wildcard cert issued by security.acme (lego) below. Using one *.gapul.net cert
  # instead of the per-vhost ACME the old Caddyfile did means 1 DNS-01 order rather
  # than 25, and no custom Caddy build with the cloudflare DNS plugin.
  certDir = config.security.acme.certs."gapul.net".directory;

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
  # LXC containers and VM105's L2TP tunnel. The one thing not carried over is
  # CT106, and only because there was nothing in it — the mullvad and wg binaries
  # are installed but /etc/wireguard is empty and its default route is the plain
  # LAN one, so it has been a tailscale node doing nothing. If a Mullvad exit node
  # is wanted, it is a fresh build, and it wants its own netns rather than this
  # host's routing table.
  imports = [
    ./homeserver-hardware.nix
    ../modules/authorized-keys.nix
    ../modules/nts-time.nix # chrony over NTS; also the time source for the Macs
    ../homelab # the Docker stacks that used to live on CT101 under dockge
    ./homeserver-fpga.nix # the CPU-experiment FPGA board on USB (openFPGALoader + UART)
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

  # Bias intel_pstate's hardware P-state choice towards efficiency. The default,
  # balance_performance, jumps to the 2.9GHz turbo on every small burst; on this
  # fanless N150 that kept the package around 60-75°C under a mostly idle load
  # (2026-10-13). The services here are I/O- and latency-tolerant, so trading a
  # little burst speed for heat is fine. Applied to every CPU at boot.
  systemd.tmpfiles.rules = [
    "w /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference - - - - balance_power"
  ];

  time.timeZone = "Asia/Tokyo";
  # Serve time to the tailnet only. The Macs cannot speak NTS (modules/nts-time.nix), so they
  # ask here, and WireGuard is what authenticates the answer. tailscale0 is a trusted interface,
  # and 123 is not opened on the LAN.
  services.chrony.extraConfig = ''
    allow 100.64.0.0/10
    allow fd7a:115c:a1e0::/48
  '';
  i18n.defaultLocale = "ja_JP.UTF-8";

  # --- Tailscale ---
  # Subnet router, taking over from CT102. Advertising the same route from two nodes
  # is safe (tailscale picks one as primary), so this can be enabled before CT102 is
  # switched off, and the old one is the fallback while cutting over.
  #
  # The remote subnet is reachable because of homelab/vpn-relay.nix; advertising it
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
    # The house; the remote network reached over the L2TP tunnel in
    # homelab/vpn-relay.nix (once advertised by VM105); and UTNET over
    # homelab/utokyo-vpn.nix. These flags only apply when the node first logs in —
    # on a running box change the routes with `tailscale set --advertise-routes=...`.
    extraUpFlags = [
      "--advertise-routes=192.168.116.0/24,192.168.1.0/24,10.80.1.0/24,130.69.0.0/16,133.11.0.0/16,157.82.0.0/16,192.51.208.0/20"
    ];
    # The host resolves through its own blocky (homelab/blocky.nix), not MagicDNS. With
    # MagicDNS, 100.100.100.100 forwarded every lookup in plaintext over the tailnet to macmini's
    # blocky (seen with tcpdump, 2026-10-31); the tailnet is not trusted to keep DNS private.
    extraSetFlags = [ "--accept-dns=false" ];
  };

  # --- TLS ---
  # DNS-01 against Cloudflare, because every name here resolves to a tailnet address
  # and no port 80 is reachable from the internet for HTTP-01.
  #
  # The credential is an env file that sops-nix installs from secrets/homelab.yaml
  # (homeserver_files, see homelab/secrets.nix):
  #   /var/lib/secrets/acme-cloudflare.env  (mode 0400, root)
  #   CF_DNS_API_TOKEN=...
  # Note the name: lego wants CF_DNS_API_TOKEN, while the Caddy plugin this replaces
  # read CF_API_TOKEN from /etc/caddy/cf.env. Same token, different variable.
  security.acme = {
    acceptTerms = true;
    # A GitHub noreply address, since this repo is public (the real one lives in
    # secrets/common.yaml). Expiry mail therefore bounces; renewal is automatic and its
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
      # Push-based checks: the dead man's switch the backup notes kept asking for. A timer
      # pushes success=true after a run (and success=false on error); if nothing arrives within
      # heartbeat.interval, gatus marks it down and alerts through the same ntfy. This is what
      # ntfy-failure@ cannot see: a timer that never fires, or a unit lost in a rebuild.
      #   curl -X POST -H "Authorization: Bearer $GATUS_PUSH_TOKEN" \
      #     "http://127.0.0.1:8084/api/v1/endpoints/timers_<name>/external?success=true"
      # The key is <group>_<name>. The token is GATUS_PUSH_TOKEN in gatus.env, which the pushing
      # units already read for the ntfy pair.
      external-endpoints = [
        {
          name = "duo-remind"; # homelab/duo-remind.nix, daily 21:00 JST
          group = "timers";
          token = "\${GATUS_PUSH_TOKEN}";
          # 21:00 + up to 5 min of RandomizedDelaySec, so a day plus slack. A missed night is
          # reported by about 22:00 the next day rather than racing the next run.
          heartbeat.interval = "25h";
          alerts = [
            {
              type = "ntfy";
              failure-threshold = 1;
              send-on-resolved = true;
              enabled = true;
            }
          ];
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
