{ pkgs, ... }:
# Healthchecks (checks.gapul.net): the dead man's switch the backup notes kept asking for.
#
# gatus and ntfy-failure@ cover "is it up" and "ran and failed". Neither notices a timer that
# never fires, a unit lost in a rebuild, or a job that runs and quietly does nothing. Here each
# job pings after a successful run and Healthchecks alerts (via the existing ntfy) when a ping is
# late. The first user is duo-remind.nix; any other timer joins by adding a slug to CHECKS in
# configs/homelab/healthchecks-bootstrap.py and pinging
#   http://127.0.0.1:8115/ping/$HC_PING_KEY/<slug>        (success)
#   http://127.0.0.1:8115/ping/$HC_PING_KEY/<slug>/fail   (failure, immediate alert)
# The key lives in /var/lib/secrets/healthchecks.env (HC_PING_KEY); jobs get a copy in their
# own env file rather than reading this one, which also holds Django's SECRET_KEY.
#
# Same hole as gatus and ntfy: all of this lives on the box it watches. The macmini's external
# monitor covers the box itself going down.
#
# SQLite in /var/lib/healthchecks, so restic already has it; backup.nix takes a consistent dump.
# No outbound email is configured: login is by password (bootstrap creates the owner), and the
# only integration is ntfy. Registration is closed; Authelia sits in front of the UI, with /ping/*
# left open so a future job on another host can ping over the tailnet.
let
  port = 8115;
in
{
  services.healthchecks = {
    enable = true;
    listenAddress = "127.0.0.1";
    inherit port;
    settingsFile = "/var/lib/secrets/healthchecks.env"; # SECRET_KEY, HC_ADMIN_*, HC_PING_KEY
    settings = {
      SITE_ROOT = "https://checks.gapul.net";
      SITE_NAME = "homeserver checks";
      REGISTRATION_OPEN = false;
      DEFAULT_FROM_EMAIL = "checks@gapul.net";
      # Pings arrive as Host: 127.0.0.1:8115 from local jobs and as checks.gapul.net via Caddy.
      ALLOWED_HOSTS = [
        "checks.gapul.net"
        "127.0.0.1"
        "localhost"
      ];
    };
  };

  # Owner, project, ping key, ntfy channel and the checks themselves, from code rather than
  # the UI. Runs after migrations on every activation and changes nothing that already matches.
  systemd.services.healthchecks-bootstrap = {
    description = "Healthchecks: owner, project, ntfy integration and checks from config";
    wantedBy = [ "healthchecks.target" ];
    after = [ "healthchecks-migration.service" ];
    requires = [ "healthchecks-migration.service" ];
    before = [ "healthchecks.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "healthchecks";
      Group = "healthchecks";
      WorkingDirectory = "/var/lib/healthchecks";
      # healthchecks-manage exports the module's environment and settingsFile itself and runs
      # manage.py directly when $USER is already the service user.
      Environment = "USER=healthchecks";
      EnvironmentFile = [ "/var/lib/secrets/gatus.env" ]; # NTFY_TOPIC, NTFY_TOKEN for the channel
      ExecStart = "${pkgs.bash}/bin/bash -c '/run/current-system/sw/bin/healthchecks-manage shell < ${../../configs/homelab/healthchecks-bootstrap.py}'";
    };
  };
}
