# Google Forms replacement. Formera keeps the form builder and response browser
# human-friendly while exposing the same operations through a documented REST
# API. Unlike Formbricks v5 it needs no Redis, analytics service, or separate
# PostgreSQL cluster: two rolling containers and one SQLite database are enough.
{
  lib,
  ...
}:

let
  backendPort = 8100;
  frontendPort = 8101;
  gatewayPort = 8102;
in
{
  virtualisation.oci-containers.containers = {
    "formera-backend" = {
      image = "ghcr.io/formeraapp/formera-backend:latest";
      environmentFiles = [ "/var/lib/secrets/formera.env" ];
      environment = {
        PORT = "8080";
        BASE_URL = "https://forms.gapul.net";
        API_URL = "https://forms.gapul.net";
        CORS_ORIGIN = "https://forms.gapul.net";
        DB_PATH = "/app/data/formera.db";
        STORAGE_TYPE = "local";
        STORAGE_LOCAL_PATH = "/app/data/uploads";
        STORAGE_LOCAL_URL = "/uploads";
        PUBLIC_INDEXABLE = "false";
        REAL_IP_HEADER = "CF-Connecting-IP";
        # The loopback port forward reaches the container through Podman's
        # default gateway (10.88.0.1), not as 127.0.0.1. The service is bound to
        # loopback, so only the local Caddy proxy can supply this header.
        TRUSTED_PROXIES = "127.0.0.1,::1,10.88.0.0/16";
        TZ = "Asia/Tokyo";
      };
      volumes = [ "/var/lib/homelab/formera:/app/data:rw" ];
      ports = [ "127.0.0.1:${toString backendPort}:8080/tcp" ];
      log-driver = "journald";
    };

    "formera-frontend" = {
      image = "ghcr.io/formeraapp/formera-frontend:latest";
      environment = {
        BASE_URL = "https://forms.gapul.net";
        API_URL = "https://forms.gapul.net";
        TZ = "Asia/Tokyo";
      };
      ports = [ "127.0.0.1:${toString frontendPort}:3000/tcp" ];
      log-driver = "journald";
    };
  };

  systemd.services = {
    "podman-formera-backend".serviceConfig.Restart = lib.mkOverride 90 "always";
    "podman-formera-frontend".serviceConfig.Restart = lib.mkOverride 90 "always";
  };

  systemd.tmpfiles.rules = [
    # Both upstream images run as uid=100, gid=101.
    "d /var/lib/homelab/formera 0700 100 101 -"
  ];

  # Cloudflared has hostname routing but not path routing. Keep a tiny local
  # gateway so the browser sees one origin while /api and /uploads reach the Go
  # backend and everything else reaches Nuxt.
  services.caddy.virtualHosts.":${toString gatewayPort}".extraConfig = ''
    route {
      # Upstream accepts anonymous 25 MB uploads independently of a form. Do not
      # expose that storage-abuse surface until it can require a form-scoped token.
      @anonymousUpload path /api/public/upload
      respond @anonymousUpload 404

      @backend path /api/* /health /health/* /uploads/*
      reverse_proxy @backend 127.0.0.1:${toString backendPort} {
        # Formera currently serializes these numeric headers as control bytes.
        # The submission is stored, but Cloudflare rejects the malformed
        # upstream response as 502. Rate limiting still happens in Formera; only
        # its broken informational response headers are removed here.
        header_down -X-Ratelimit-Limit
        header_down -X-Ratelimit-Remaining
      }
      reverse_proxy 127.0.0.1:${toString frontendPort}
    }
  '';
}
