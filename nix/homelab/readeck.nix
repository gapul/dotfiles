# Read later (a Pocket replacement).
#
# How it fits with what's already here: archivebox is for "save the whole thing before it
# disappears", not a reading tool. miniflux is subscriptions that scroll away once read.
# Between the two there was no "sit down and read it later". readeck fills just that gap.
#
# Chosen for being light. karakeep has more features (AI tagging, native apps), but it brings
# Next.js with meilisearch and a headless Chrome. readeck is a single Go binary plus SQLite,
# among the smallest things on this box. With only 6.5GB of free memory and calnode going in
# too, the lighter one won.
#
# miniflux 2.3.3 knows readeck as an integration out of the box (confirmed in the binary
# alongside wallabag / linkding / shiori / karakeep). Things found via subscriptions can be
# dropped in on the spot, so the two mesh better than used separately. The integration is set
# up by entering readeck's URL and API token in miniflux's UI; it can't be declared.
#
# No secrets needed. The secret key is generated on first start and stored in the data
# directory (0.23.1's "Use generated secret key during first run"). The admin user is also
# created in the browser on first run. So there are no files to place by hand before rebuild.
{
  lib,
  ...
}:

{
  # A new service, so there's no data migrating from the old host. Create the bind-mount source first.
  systemd.tmpfiles.rules = [
    "d /var/lib/homelab/readeck 0700 root root -"
  ];

  virtualisation.oci-containers.containers."readeck" = {
    # Codeberg's registry, not Docker Hub. It's stable on the 0.23 series, so latest is fine,
    # matching the other stacks (calnode was pinned to 0.2 because it's still on v0.2 with
    # commits landing several times a day; the situation differs here).
    image = "codeberg.org/readeck/readeck:latest";
    environment = {
      # HOST is already 0.0.0.0 in the image, so this is just to be sure. PORT is set to an
      # empty string by the image (confirmed with podman image inspect), and without giving it
      # here we'd depend on how the default gets interpreted, so set it explicitly.
      "READECK_SERVER_HOST" = "0.0.0.0";
      "READECK_SERVER_PORT" = "8000";
      # Behind Caddy, so the Host it presents must be explicitly allowed.
      "READECK_ALLOWED_HOSTS" = "read.gapul.net";
      "READECK_USE_X_FORWARDED" = "1";
      # Goes to journald, so a readable format beats JSON.
      "READECK_LOG_FORMAT" = "text";
    };
    volumes = [
      "/var/lib/homelab/readeck:/readeck:rw"
    ];
    ports = [
      "127.0.0.1:18087:8000/tcp"
    ];
    log-driver = "journald";
  };

  systemd.services."podman-readeck" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
  };
}
