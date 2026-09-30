# attic runs directly via the nixpkgs module. Only postgres remains a container derived from
# compose2nix. Originally /opt/stacks/attic/compose.yaml.
#
# The server was moved to the module because server.toml had been placed by hand in
# /var/lib/homelab/attic, outside the declaration, and the image was :latest. The settings now
# live here.
#
# postgres stays as is because the container's postgres:16-alpine created the cluster with musl.
# Opening the same PGDATA with a glibc postgres changes collation, which can corrupt text indexes.
# Moving it would have to go through pg_dump, so that is for another day.
{
  pkgs,
  lib,
  config,
  ...
}:

let
  # The module injects a default `database.url = "sqlite://…"` into settings. attic prefers values
  # from the config file over environment variables, so passing ATTIC_SERVER_DATABASE_URL has no
  # effect and it creates an empty SQLite and uses that instead (this actually happened). sqlite
  # cannot come back, since the original setup dropped it after CI's parallel pushes clogged the
  # connection pool.
  #
  # But the URL is connection credentials in itself, and the store is world-readable. Keep the
  # declaration as is and inject only the URL from an environment variable at startup. Same trick
  # as vpn-relay.nix.
  serverToml = (pkgs.formats.toml { }).generate "atticd-server.toml" (
    lib.recursiveUpdate config.services.atticd.settings { database.url = "@DB_URL@"; }
  );
  mkServerToml = pkgs.writeShellScript "atticd-server-toml" ''
    set -eu
    ${pkgs.gnused}/bin/sed "s#@DB_URL@#$ATTIC_SERVER_DATABASE_URL#" \
      ${serverToml} > /run/atticd/server.toml
    chmod 600 /run/atticd/server.toml
  '';
in
{
  services.atticd = {
    enable = true;
    # Holds ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64 and the postgres URL
    # (ATTIC_SERVER_DATABASE_URL). The URL is connection credentials in itself, so it is not written
    # in settings. The module's config check runs with a dummy URL, so it passes even without
    # database.url.
    environmentFile = "/var/lib/secrets/attic.env";
    settings = {
      # Caddy forwards cache.gapul.net here. The port matches the one the container used to publish
      # as 8083:8080, so the reverse proxy side needs no change.
      listen = "127.0.0.1:8083";
      storage = {
        type = "local";
        # 2.3GB. /srv is a dataset with automatic snapshots turned off, so the cache
        # isn't retained across generations.
        path = "/srv/attic/storage";
      };
      chunking = {
        nar-size-threshold = 65536;
        min-size = 16384;
        avg-size = 65536;
        max-size = 262144;
      };
      compression.type = "zstd";
      garbage-collection.interval = "12 hours";
    };
  };

  # The module's default is DynamicUser, whose UID can change across restarts. The storage already
  # exists in /srv with a fixed owner, so use a plain system user.
  users.users.atticd = {
    isSystemUser = true;
    group = "atticd";
  };
  users.groups.atticd = { };
  systemd.services.atticd = {
    after = [ "podman-attic-db.service" ];
    wants = [ "podman-attic-db.service" ];
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      RuntimeDirectory = "atticd";
      RuntimeDirectoryMode = "0700";
      ExecStartPre = [ "${mkServerToml}" ];
      ExecStart = lib.mkForce "${lib.getExe config.services.atticd.package} -f /run/atticd/server.toml --mode ${config.services.atticd.mode}";
    };
  };

  # Containers
  virtualisation.oci-containers.containers."attic-db" = {
    image = "docker.io/library/postgres:16-alpine";
    environmentFiles = [ "/var/lib/secrets/attic.env" ];
    environment = {
      "POSTGRES_DB" = "attic";
      "POSTGRES_USER" = "attic";
    };
    volumes = [
      "/srv/attic/pgdata:/var/lib/postgresql/data:rw"
    ];
    # atticd connects from the host. In the compose days it was container-to-container, so there
    # was no publish. Expose it on loopback only.
    #
    # The host side is 5433. 5432 is used by atuin — a nixpkgs update made services.atuin require a
    # native postgres (atuin.nix in 26.05), which grabbed 5432 first, so attic-db couldn't bind and
    # went into a restart loop.
    # Keep the port in DB_URL in sync (/var/lib/secrets/attic.env).
    ports = [
      "127.0.0.1:5433:5432/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--health-cmd=pg_isready -U attic -d attic"
      "--health-start-period=30s"
      "--health-interval=10s"
      "--health-retries=10"
      "--health-timeout=5s"
      "--network-alias=db"
      "--network=attic_default"
    ];
  };
  systemd.services."podman-attic-db" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "podman-network-attic_default.service"
    ];
    requires = [
      "podman-network-attic_default.service"
    ];
    partOf = [
      "podman-compose-attic-root.target"
    ];
    wantedBy = [
      "podman-compose-attic-root.target"
    ];
  };

  # Networks
  systemd.services."podman-network-attic_default" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "podman network rm -f attic_default";
    };
    script = ''
      podman network inspect attic_default || podman network create attic_default
    '';
    partOf = [ "podman-compose-attic-root.target" ];
    wantedBy = [ "podman-compose-attic-root.target" ];
  };

  # Root service
  # When started, this will automatically create all resources and start
  # the containers. When stopped, this will teardown all resources.
  systemd.targets."podman-compose-attic-root" = {
    unitConfig = {
      Description = "Root target generated by compose2nix.";
    };
    wantedBy = [ "multi-user.target" ];
  };
}
