# Receiver that stores iPhone Health data at home (health.gapul.net).
#
# The sender is PulsHealth (iOS, Apache-2.0, distributed on the App Store). It reads HealthKit
# read-only, and after sending the full history it POSTs deltas as gzip NDJSON. It sends only to
# the configured server, never to the developer or third parties, which was verified in the
# source (2026-09-15).
#
# The receiver is not the heavy official stack (TimescaleDB + Go + Grafana) but the bundled
# Python + SQLite example brought into configs/homelab/puls-receiver, with a cap on decompressed
# size and a GET /v1/stats added. It runs on the standard library alone and the DB is a single file.
#
# Auth is the bearer token held by the app (PULS_TOKEN in /var/lib/secrets/puls.env), so
# Authelia is not put in front of the vhost. The app's URL validation does not allow plain http
# to tailnet 100.x addresses, so it goes through Caddy's HTTPS.
#
# DynamicUser puts the DB in /var/lib/private/puls (0700), so reading it directly needs root.
# To see what has arrived, ask the service instead:
#   curl -s -H "Authorization: Bearer $PULS_TOKEN" http://127.0.0.1:8105/v1/stats
{ pkgs, ... }:

{
  systemd.services.puls-receiver = {
    description = "PulsHealth receiver (Apple Health → SQLite)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    environment = {
      PULS_DB = "/var/lib/puls/health.db";
      PULS_BIND = "127.0.0.1";
      PULS_PORT = "8105";
    };
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${../../configs/homelab/puls-receiver/receiver.py}";
      EnvironmentFile = "/var/lib/secrets/puls.env";
      DynamicUser = true;
      StateDirectory = "puls";
      StateDirectoryMode = "0700";
      Restart = "always";
      RestartSec = 10;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      MemoryMax = "1G";
    };
  };
}
