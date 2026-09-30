# Hand files to other people. A WeTransfer replacement.
#
# Sync between my own devices is covered by syncthing and samba, so the gap was "handing something
# to someone once". A collaboration box like Nextcloud is not needed.
#
# It issues links with an expiry, download count and password, and the files themselves are
# deleted when they expire. The point is that nothing lingers after handing it over, which is why
# it runs on my own box.
#
# Goes through the tunnel, like cal / poll / split. The recipient is outside the tailnet, so
# caddy's vhost can't reach them. Point DNS at this tunnel's CNAME.
{
  lib,
  ...
}:

let
  privatePort = 18094;
in
{
  virtualisation.oci-containers.containers."pingvin-share" = {
    # Original Pingvin Share was archived. X is its directly maintained fork.
    # Keep the rolling tag: this homelab deliberately follows current releases,
    # while container-auto-update supplies the failed-start rollback path.
    image = "ghcr.io/smp46/pingvin-share-x:latest";
    environment = {
      "TZ" = "Asia/Tokyo";
      "CONFIG_FILE" = "/opt/app/config.yaml";
      # The URL embedded in issued links. If it is wrong, links you hand out point at an internal
      # address and the recipient can't open them.
      "APP_URL" = "https://send.gapul.net";
      # It sits behind the tunnel, so the client IP comes from headers.
      "TRUST_PROXY" = "true";
    };
    volumes = [
      "${../../configs/homelab/pingvin-share.yaml}:/opt/app/config.yaml:ro"
      "/var/lib/homelab/pingvin-share/data:/opt/app/backend/data:rw"
    ];
    ports = [ "127.0.0.1:${toString privatePort}:3000/tcp" ];
    log-driver = "journald";
  };
  systemd.services."podman-pingvin-share".serviceConfig.Restart = lib.mkOverride 90 "always";

  systemd.tmpfiles.rules = [
    "d /var/lib/homelab/pingvin-share 0700 root root -"
    # Pingvin drops to uid/gid 1000. SQLite needs directory write access for
    # journals/WAL files, not merely write access to pingvin-share.db itself.
    "d /var/lib/homelab/pingvin-share/data 0700 1000 1000 -"
  ];
}
