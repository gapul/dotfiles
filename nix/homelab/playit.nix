# playit.gg agent — the public door to the Minecraft server on the Mac mini.
#
# The game server itself runs natively on macOS (see hosts/macmini.nix); this box only relays.
# Why here and not next to the server: playit ships no macOS binary, and the Mac mini has no
# container runtime left. The last hop is LAN/tailnet, so the added latency is the trip to
# playit's edge, which is what a friend outside the tailnet would pay anyway.
#
# The tunnel's target is set in playit's web panel, not here: the agent only carries a secret and
# does what the account tells it. Host networking so it can reach the Mac mini over tailscale.
{
  lib,
  ...
}:

{
  virtualisation.oci-containers.containers."playit" = {
    image = "ghcr.io/playit-cloud/playit-agent:latest";
    # SECRET_KEY. Issued once by `playit-cli claim exchange`; the panel can revoke it.
    environmentFiles = [ "/var/lib/secrets/playit.env" ];
    log-driver = "journald";
    extraOptions = [ "--network=host" ];
  };
  systemd.services."podman-playit" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
  };
}
