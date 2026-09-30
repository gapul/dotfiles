# Bill splitting (in place of walica / Splitwise). It is used with other people, so it is
# exposed outside the tailnet.
#
# There is no authentication. A group can be opened by anyone who knows its URL, the same idea
# as walica's "no account needed, share the link". So neither a login system nor SMTP is
# needed; the only thing it needs to run is a DB.
#
# Image attachments and receipt scanning (OpenAI) stay disabled by default. The former needs S3,
# and the latter would send receipts to an external API. Neither is needed for now.
{
  pkgs,
  lib,
  ...
}:

let
  privatePort = 18090;
in
{
  # A single level, for the same reason as rallly.nix. Trying to nest under /var/lib/homelab
  # gets rejected by tmpfiles as an unsafe path transition (see calnode.nix).
  #
  # The owner is 70 rather than root because the postgres image runs as uid 70.
  # With root-owned 0700, startup fails with `mkdir: can't create directory
  # '/var/lib/postgresql/18/': Permission denied`. The existing miniflux/db is also owned by uid 70.
  systemd.tmpfiles.rules = [
    "d /var/lib/homelab/spliit-db 0700 70 70 -"
  ];

  virtualisation.oci-containers.containers."spliit" = {
    image = "ghcr.io/spliit-app/spliit:latest";
    # POSTGRES_PRISMA_URL and POSTGRES_URL_NON_POOLING. Both are connection strings containing
    # the password, so they go in the env file. See README.md.
    environmentFiles = [ "/var/lib/secrets/spliit.env" ];
    environment = {
      "BASE_URL" = "https://split.gapul.net";
      # Used in yen, so the default currency is JPY. It can be changed per group.
      "DEFAULT_CURRENCY_CODE" = "JPY";
    };
    ports = [
      "127.0.0.1:${toString privatePort}:3000/tcp"
    ];
    dependsOn = [ "spliit-db" ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=spliit"
      "--network=spliit_default"
    ];
  };
  systemd.services."podman-spliit" = {
    serviceConfig.Restart = lib.mkOverride 90 "always";
    after = [ "podman-network-spliit_default.service" ];
    requires = [ "podman-network-spliit_default.service" ];
  };

  virtualisation.oci-containers.containers."spliit-db" = {
    image = "docker.io/library/postgres:18-alpine";
    environmentFiles = [ "/var/lib/secrets/spliit.env" ];
    environment = {
      "POSTGRES_DB" = "spliit";
      "POSTGRES_USER" = "spliit";
    };
    volumes = [
      "/var/lib/homelab/spliit-db:/var/lib/postgresql:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--health-cmd=[\"pg_isready\", \"-U\", \"spliit\"]"
      "--health-start-period=30s"
      "--health-interval=10s"
      "--health-retries=5"
      "--health-timeout=5s"
      "--network-alias=db"
      "--network=spliit_default"
    ];
  };
  systemd.services."podman-spliit-db" = {
    serviceConfig.Restart = lib.mkOverride 90 "always";
    after = [ "podman-network-spliit_default.service" ];
    requires = [ "podman-network-spliit_default.service" ];
  };

  systemd.services."podman-network-spliit_default" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "podman network rm -f spliit_default";
    };
    script = ''
      podman network inspect spliit_default || podman network create spliit_default
    '';
    wantedBy = [ "multi-user.target" ];
  };
}
