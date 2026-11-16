# multi-scrobbler: one place that collects listening history from every player and forwards it
# to ListenBrainz (user copy4711). Added 2026-11-15.
#
# Why a server: iOS doesn't let a third-party app see what other apps are playing, so there is
# no Pano Scrobbler for the iPhone. Each player is watched from here instead:
#   - Navidrome (Amperfy on the iPhone): Navidrome's own ListenBrainz scrobbler, pointed at this
#     service's ListenBrainz-compatible endpoint instead of api.listenbrainz.org. Push-based, so
#     it doesn't keep the lazy navidrome container awake the way polling the Subsonic API would.
#     Each Navidrome user still has to switch "Scrobble to ListenBrainz" on in their personal
#     settings once (any token works; this endpoint doesn't check one).
#   - YouTube Music: polled by cookie when YTM_ID/YTM_COOKIE are added to the env file. Use a
#     separate private-window login, not the cookie of the macmini Chrome profile that Mopidy
#     refreshes every two hours: two clients rotating the same session invalidate it.
# The main Mac's Mopidy already submits to ListenBrainz directly and stays that way.
#
# The env file (homeserver_files/multi-scrobbler.env in secrets/homelab.yaml) holds LZ_USER and
# LZ_TOKEN (the same token as listenbrainz.token in secrets/darwin.yaml), plus YTM_ID and
# YTM_COOKIE once YouTube Music is set up. Component IDs go there too, never in `environment`:
# a source whose ID is set without its credential fails to start.
{
  pkgs,
  lib,
  ...
}:

{
  # The image runs as the distroless nonroot user (65532) and exits at startup when /config
  # isn't writable, so the bind-mounted directory has to belong to that user.
  systemd.tmpfiles.rules = [
    "d /var/lib/homelab/multi-scrobbler 0700 65532 65532 -"
  ];

  virtualisation.oci-containers.containers."multi-scrobbler" = {
    image = "ghcr.io/foxxmd/multi-scrobbler:latest";
    environment = {
      "TZ" = "Asia/Tokyo";
      "BASE_URL" = "https://scrobble.gapul.net";
      # Authelia sits in front of the dashboard (homeserver-sites.nix), and the only other
      # caller is Navidrome over the private network below, so a second login adds nothing.
      "AUTH_MODE" = "disabled";
      # The ListenBrainz-compatible ingress Navidrome submits to. Without a token it accepts
      # every submission, which is fine on a network only Navidrome shares.
      "LZE_ID" = "navidrome";
      "LZ_ID" = "listenbrainz";
    };
    environmentFiles = [ "/var/lib/secrets/multi-scrobbler.env" ];
    volumes = [
      "/var/lib/homelab/multi-scrobbler:/config:rw"
    ];
    ports = [
      "127.0.0.1:8122:9078/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=multi-scrobbler"
      "--network=scrobble"
    ];
  };

  # Navidrome joins a network owned by this module rather than multi-scrobbler joining
  # navidrome_default: lazy-http-services stops navidrome's compose target when idle, and the
  # network service that is part of it runs `podman network rm -f` on the way down.
  virtualisation.oci-containers.containers."navidrome" = {
    environment."ND_LISTENBRAINZ_BASEURL" = "http://multi-scrobbler:9078/1/";
    extraOptions = [ "--network=scrobble" ];
  };

  systemd.services."podman-network-scrobble" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      podman network inspect scrobble || podman network create scrobble
    '';
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services."podman-multi-scrobbler" = {
    after = [ "podman-network-scrobble.service" ];
    requires = [ "podman-network-scrobble.service" ];
    serviceConfig.Restart = lib.mkOverride 90 "always";
  };
  systemd.services."podman-navidrome" = {
    after = [ "podman-network-scrobble.service" ];
    requires = [ "podman-network-scrobble.service" ];
  };
}
