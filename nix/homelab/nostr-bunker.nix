# Signet: a self-hosted NIP-46 remote signer for the gapul@gapul.net Nostr identity
# (social.nix, npub16t57vts9…q08y5). Upstream publishes no container image — the
# only documented path is a local docker compose build — so this builds from a
# pinned commit instead of pinning a digest, which is what free-games-claimer.nix
# does for the same reason (a stack that ends up holding a real credential).
# Verified by building and smoke-testing this exact commit before pinning it here:
# both images build clean and the daemon reaches /health after a fresh migration.
#
# Bump signetRev by hand and read the diff first — this handles the actual signing
# key for @gapul@gapul.net, not a throwaway identity.
#
# Only the UI (4174) is reachable, and only through Caddy + Authelia on the tailnet
# (bunker.gapul.net in homeserver.nix's `sites`). The daemon's REST API (3000) ships
# with no built-in auth — Signet's own startup log says so outright — so it is never
# published to the host; signet-ui reaches it by container name on signet_net instead.
#
# This file does not import the key. That happens by hand, once, after this is
# deployed:
#   ssh homeserver
#   sudo podman run --rm -it -v /var/lib/homelab/signet/config:/app/config signet:local \
#     add --name gapul --config /app/config/signet.json
# and paste the nsec form of /var/lib/secrets/nostr.env's NOSTR_PRIVATE_KEY (hex) when
# prompted, choosing NIP-49 encryption with a passphrase. Never as a command argument —
# only at the interactive prompt, so it doesn't land in shell history or `ps`.
{
  pkgs,
  lib,
  ...
}:
let
  signetRev = "509395cf180908f3dbd69b6ae8d6cb94003a6152"; # 2026-09-21, v1.20.0
  signetSrcDir = "/var/lib/homelab/signet/src";
  configDir = "/var/lib/homelab/signet/config";
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/homelab/signet 0755 root root -"
    # uid/gid 1000 is the image's unprivileged `node` user (checked with `podman run
    # --user root signet:local id node`); the daemon writes its sqlite db and
    # NIP-49-encrypted key material here.
    "d ${configDir} 0700 1000 1000 -"
  ];

  # Builds both images locally; nothing here ever pulls from a registry (there is
  # none). Re-run by hand after bumping signetRev: `systemctl restart signet-build`
  # then `systemctl restart podman-signet podman-signet-ui`.
  systemd.services.signet-build = {
    description = "Build Signet (NIP-46 signer) images from a pinned commit";
    path = [
      pkgs.git
      pkgs.gnused
      pkgs.podman
    ];
    # Skip the rebuild once this revision's marker exists, so a normal switch
    # doesn't reclone and rebuild on every activation.
    unitConfig.ConditionPathExists = "!${configDir}/../.built-${signetRev}";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      rm -rf ${signetSrcDir}
      git clone https://github.com/Letdown2491/signet.git ${signetSrcDir}
      git -C ${signetSrcDir} checkout ${signetRev}
      # Podman deliberately has no unqualified registry search path. Keep the
      # pinned upstream source intact on Git, but make its official Node base
      # image explicit in the disposable checkout before building.
      sed -i 's|^FROM node:|FROM docker.io/library/node:|' \
        ${signetSrcDir}/apps/signet/Dockerfile \
        ${signetSrcDir}/apps/signet-ui/Dockerfile
      podman build -t signet:local -f ${signetSrcDir}/apps/signet/Dockerfile ${signetSrcDir}
      podman build -t signet-ui:local -f ${signetSrcDir}/apps/signet-ui/Dockerfile ${signetSrcDir}
      rm -f /var/lib/homelab/signet/.built-*
      touch /var/lib/homelab/signet/.built-${signetRev}
    '';
  };

  systemd.services."podman-network-signet_net" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "${pkgs.podman}/bin/podman network rm -f signet_net";
    };
    script = ''
      podman network inspect signet_net || podman network create signet_net
    '';
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers.signet = {
    image = "signet:local";
    pull = "never"; # only ever produced by signet-build; there is nothing to pull
    # container-auto-update.nix defaults every container to the "registry" policy,
    # which requires a fully-qualified, pullable image — this one is neither, and
    # bumps are meant to be manual (read the diff first) anyway. Not "local" either:
    # that policy would let the daily timer swap in whatever signet-build last
    # produced, which defeats the point of pinning signetRev by hand.
    labels."io.containers.autoupdate" = lib.mkForce "disabled";
    volumes = [ "${configDir}:/app/config:rw" ];
    environment = {
      # Where Signet sends people for the request-approval flow. Must match the
      # Caddy vhost below, not the container's own port.
      EXTERNAL_URL = "https://bunker.gapul.net";
    };
    log-driver = "journald";
    extraOptions = [
      "--network-alias=signet"
      "--network=signet_net"
    ];
  };
  systemd.services."podman-signet" = {
    after = [
      "signet-build.service"
      "podman-network-signet_net.service"
    ];
    requires = [
      "signet-build.service"
      "podman-network-signet_net.service"
    ];
    serviceConfig.Restart = lib.mkOverride 90 "always";
  };

  virtualisation.oci-containers.containers.signet-ui = {
    image = "signet-ui:local";
    pull = "never";
    labels."io.containers.autoupdate" = lib.mkForce "disabled"; # see signet, above
    # 127.0.0.1 only: reached through Caddy (tailnet + Authelia), never directly.
    ports = [ "127.0.0.1:4174:4174/tcp" ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=signet-ui"
      "--network=signet_net"
    ];
  };
  systemd.services."podman-signet-ui" = {
    after = [
      "signet-build.service"
      "podman-network-signet_net.service"
      "podman-signet.service"
    ];
    requires = [
      "signet-build.service"
      "podman-network-signet_net.service"
    ];
    serviceConfig.Restart = lib.mkOverride 90 "always";
  };
}
