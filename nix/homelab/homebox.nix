# Inventory of belongings (Homebox). What I own, where it is, when and for how much it was
# bought, and when the warranty ends.
#
# The main user is an LLM, not a person, which registers and searches via the REST API. API
# keys (starting with hb_, inheriting the issuing user's permissions) are available since
# v0.26, so scripts don't need to hold a password. nixpkgs' homebox is 0.25 and has no API
# keys, so this uses the official image rather than the module. In 0.26 the items/locations
# APIs were merged into /v1/entities.
#
# Original receipts and warranty cards live in Paperless; this only holds the Paperless URL.
# A single Go binary plus SQLite, under 50MB of memory when idle.
{
  lib,
  ...
}:

{
  systemd.tmpfiles.rules = [
    "d /var/lib/homelab/homebox 0700 root root -"
  ];

  virtualisation.oci-containers.containers."homebox" = {
    image = "ghcr.io/sysadminsmedia/homebox:latest";
    # HBOX_AUTH_API_KEY_PEPPER (random, 32+ characters). Since 0.26 it won't start without it.
    # Changing it invalidates every issued API key.
    environmentFiles = [ "/var/lib/secrets/homebox.env" ];
    environment = {
      # The account was created on 2026-09-26, so registration is closed. Even though it's
      # tailnet-only, there's no reason to leave registration open. Set to true only
      # temporarily when adding accounts.
      "HBOX_OPTIONS_ALLOW_REGISTRATION" = "false";
      "HBOX_LOG_FORMAT" = "text";
      "HBOX_WEB_MAX_UPLOAD_SIZE" = "20";
    };
    volumes = [
      "/var/lib/homelab/homebox:/data:rw"
    ];
    ports = [
      "127.0.0.1:8104:7745/tcp"
    ];
    log-driver = "journald";
  };

  systemd.services."podman-homebox" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
  };
}
