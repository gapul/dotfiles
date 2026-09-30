# Booking page (a Calendly replacement). Not cal.com.
#
# Why not cal.com: it's a Next.js monorepo that brings Postgres and Redis along and takes
# 1-1.5GB just sitting idle. All we want is "publish free time and let someone grab a slot",
# and that price doesn't pay off. Calnode is a single Go binary plus SQLite and does the
# same in a few tens of MB. That's why, unlike the other stacks, there's no DB container.
#
# Free/busy comes over CalDAV from the radicale already running on this box. The
# integration is registered with an app-password in the admin UI, not via environment
# variables, so nothing goes here. Bookings are written back to radicale over the same
# connection.
#
# Tracks latest per the rolling-release policy. State is a single SQLite DB, so the daily
# restic backup and the monthly restore drill are the safety net for updates.
{
  lib,
  ...
}:

{
  # A new service, so there's no data migrating from the old host. Create the bind-mount source first.
  #
  # Only one level deep because tmpfiles can't create a second level under this tree.
  # /var/lib/homelab itself is owned by uid 100000 (podman's userns root); after creating a
  # root-owned calnode/ under it, descending further makes systemd refuse with
  # "Detected unsafe path transition /var/lib/homelab (owned by 100000) →
  # /var/lib/homelab/calnode (owned by root)". It's a safeguard against following a path
  # whose owner changes from non-root to root, and tmpfiles settings can't turn it off.
  #
  # This actually bit on the first rebuild on 2026-08-20. calnode/ got created but
  # calnode/data/ didn't, and podman failed to start with 125: `statfs
  # /var/lib/homelab/calnode/data: no such file or directory` (podman only auto-creates
  # one level directly under the bind target, not nested ones).
  #
  # So drop the data/ level and use this directory itself as the mount source.
  # That matches readeck, which runs fine with the same layout.
  systemd.tmpfiles.rules = [
    "d /var/lib/homelab/calnode 0700 root root -"
  ];

  virtualisation.oci-containers.containers."calnode" = {
    image = "ghcr.io/calnode/calnode:latest";
    # CALNODE_ENCRYPTION_KEY and CALNODE_RECOVERY_SECRET. See README.md.
    # BASE_URL is https, so the app refuses to start without the former.
    environmentFiles = [ "/var/lib/secrets/calnode.env" ];
    environment = {
      # Include the scheme. Being https is itself the switch for production mode
      # (secure cookies and a mandatory encryption key).
      "BASE_URL" = "https://booking.gapul.net";
      "DATABASE_URL" = "sqlite:///data/calnode.db";
      "PORT" = "3000";
    };
    volumes = [
      "/var/lib/homelab/calnode:/data:rw"
    ];
    # The container's 3000 is already taken on the host by homepage, so publish on 8086.
    ports = [
      "8086:3000/tcp"
    ];
    log-driver = "journald";
  };

  systemd.services."podman-calnode" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
  };
}
