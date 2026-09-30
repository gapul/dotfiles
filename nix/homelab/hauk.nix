# Temporarily share current location with others. A tool for sending "I'm here now" as an
# expiring URL.
#
# Different role from Dawarich. That one accumulates my own track (a Google Timeline
# replacement) and isn't meant for showing others. This one, conversely, **never writes
# location to disk**. It lives in memcached only during the session and disappears when it
# ends. Having no history is the feature.
#
# It was previously ruled out because there was only an Android client, but an iOS client
# came out in 2026 ("Hauk" on the App Store, by NickBouwhuis). Requires iOS 18.6 or later.
#
# The other party is outside the tailnet, so like cal / poll / split it goes through the tunnel.
# DNS must be a CNAME to this tunnel.
#
# Configuration is placed by hand at /var/lib/homelab/hauk/config.php (it contains the
# password hash, so it's kept out of this tree). See README.md.
{
  lib,
  ...
}:

{
  virtualisation.oci-containers.containers."hauk" = {
    image = "docker.io/bilde2910/hauk:latest";
    environment = {
      "TZ" = "Asia/Tokyo";
    };
    volumes = [
      "/var/lib/homelab/hauk:/etc/hauk:rw"
    ];
    ports = [ "8095:80/tcp" ];
    log-driver = "journald";
  };
  systemd.services."podman-hauk".serviceConfig.Restart = lib.mkOverride 90 "always";

  systemd.tmpfiles.rules = [
    # Apache runs as www-data (uid/gid 33) inside the container.  The config
    # contains only a password hash, but it still has to be traversable/readable
    # by that process; 0700 root:root made the backend report config.php missing.
    "d /var/lib/homelab/hauk 0750 root 33 -"
    "z /var/lib/homelab/hauk/config.php 0640 root 33 -"
  ];
}
