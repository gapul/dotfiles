# Scheduling polls (instead of Chouseisan / Doodle). For the club, so it opens from outside
# the tailnet.
#
# Division of labor with calnode: that one is booking, this one is voting. Booking is an
# exclusive mechanism where "one person takes a published free slot and the taken slot
# disappears"; scheduling is a non-exclusive one where "candidate dates are listed, everyone
# marks yes/no on all of them, and you look for the overlap". The former can't do the latter
# (the moment one person holds a slot, nobody else can mark the same day). calnode's feature
# list has nothing equivalent to voting or tallying. Conclusion: a separate service is needed.
#
# Participants can vote as guests without an account. Creators can also create as guests, so
# the minimum works even without SMTP. If logging in to manage polls becomes desirable, add
# SMTP then (just put SMTP_* in rallly.env).
#
# The app tracks latest under the rolling-release policy. The DB is kept separately on the
# PostgreSQL 18 series, with pre-update backups and restore drills to prepare for one-way
# migrations.
{
  pkgs,
  lib,
  ...
}:

let
  privatePort = 18089;
in
{
  # Bind mount sources. Kept to **one level only**. /var/lib/homelab itself is owned by
  # uid 100000 (podman's userns root), so creating a root-owned directory under it and then
  # descending further makes systemd refuse with an unsafe path transition. Actually hit
  # this with calnode (details in calnode.nix). So the db directory sits alongside, not nested.
  #
  # The owner is 70 rather than root because the postgres image runs as uid 70.
  # With root-owned 0700, startup fails with `mkdir: can't create directory
  # '/var/lib/postgresql/18/': Permission denied`. The existing miniflux/db was also owned by uid 70.
  systemd.tmpfiles.rules = [
    "d /var/lib/homelab/rallly-db 0700 70 70 -"
  ];

  virtualisation.oci-containers.containers."rallly" = {
    # Docker Hub, but hosts/homeserver.nix swaps docker.io for mirror.gcr.io, so pull
    # limits don't apply.
    image = "docker.io/lukevella/rallly:latest";
    # DATABASE_URL / SECRET_PASSWORD / SUPPORT_EMAIL. See README.md.
    # SECRET_PASSWORD must be 32+ characters or the app rejects it at startup (validated with zod).
    environmentFiles = [ "/var/lib/secrets/rallly.env" ];
    environment = {
      # When self-hosted this is read at runtime, not at build time.
      "NEXT_PUBLIC_BASE_URL" = "https://poll.gapul.net";
    };
    ports = [
      "127.0.0.1:${toString privatePort}:3000/tcp"
    ];
    dependsOn = [ "rallly-db" ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=rallly"
      "--network=rallly_default"
    ];
  };
  systemd.services."podman-rallly" = {
    serviceConfig.Restart = lib.mkOverride 90 "always";
    after = [ "podman-network-rallly_default.service" ];
    requires = [ "podman-network-rallly_default.service" ];
  };

  virtualisation.oci-containers.containers."rallly-db" = {
    # This is what upstream's compose specifies. The 18 series moved PGDATA, but the parent
    # directory is mounted as a whole so it doesn't matter (upstream does the same).
    image = "docker.io/library/postgres:18-alpine";
    environmentFiles = [ "/var/lib/secrets/rallly.env" ];
    environment = {
      "POSTGRES_DB" = "rallly";
      "POSTGRES_USER" = "rallly";
    };
    volumes = [
      "/var/lib/homelab/rallly-db:/var/lib/postgresql:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--health-cmd=[\"pg_isready\", \"-U\", \"rallly\"]"
      "--health-start-period=30s"
      "--health-interval=10s"
      "--health-retries=5"
      "--health-timeout=5s"
      "--network-alias=db"
      "--network=rallly_default"
    ];
  };
  systemd.services."podman-rallly-db" = {
    serviceConfig.Restart = lib.mkOverride 90 "always";
    after = [ "podman-network-rallly_default.service" ];
    requires = [ "podman-network-rallly_default.service" ];
  };

  systemd.services."podman-network-rallly_default" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "podman network rm -f rallly_default";
    };
    script = ''
      podman network inspect rallly_default || podman network create rallly_default
    '';
    wantedBy = [ "multi-user.target" ];
  };
}
