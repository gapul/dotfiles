# Google Forms replacement. Formera keeps the form builder and response browser
# human-friendly while exposing the same operations through a documented REST
# API. Unlike Formbricks v5 it needs no Redis, analytics service, or separate
# PostgreSQL cluster: two rolling containers and one SQLite database are enough.
{
  formera-source,
  lib,
  pkgs,
  ...
}:

let
  backendPort = 8100;
  frontendPort = 8101;
  gatewayPort = 8102;
  privateBackendPort = 18100;
  privateFrontendPort = 18101;

  # Temporary compatibility build. Upstream writes integer rate-limit values
  # as control bytes, which Go reverse proxies correctly reject. Tracking the
  # source as a flake input keeps this rolling; remove the patch and image build
  # when upstream changes these conversions to strconv.Itoa itself.
  formeraBackend = pkgs.buildGoModule {
    pname = "formera-backend";
    version = "unstable-${builtins.substring 0 8 formera-source.rev}";
    src = "${formera-source}/backend";
    vendorHash = "sha256-OM81eTs8rXc2RBXXHsUXxjXgwmuSE/CNKQ7iMI0byak=";
    postPatch = ''
      substituteInPlace internal/middleware/ratelimit.go \
        --replace-fail '"net/http"' '"net/http"
        "strconv"' \
        --replace-fail 'string(rune(config.Rate))' 'strconv.Itoa(config.Rate)' \
        --replace-fail 'string(rune(remaining))' 'strconv.Itoa(remaining)' \
        --replace-fail 'string(rune(limiter.Remaining(key)))' 'strconv.Itoa(limiter.Remaining(key))'
    '';
    env.CGO_ENABLED = "1";
    subPackages = [ "cmd/server" ];
  };

  formeraBackendImage = pkgs.dockerTools.buildLayeredImage {
    name = "localhost.local/formera-backend";
    tag = "latest";
    contents = [
      pkgs.cacert
      pkgs.tzdata
    ];
    config = {
      Cmd = [
        "${formeraBackend}/bin/server"
        "serve"
      ];
      Env = [ "PORT=8080" ];
      WorkingDir = "/app";
      User = "100:101";
    };
    extraCommands = ''
      mkdir -p app/data
    '';
    fakeRootCommands = ''
      chown -R 100:101 app
      chmod 0700 app/data
    '';
  };
in
{
  virtualisation.oci-containers.containers = {
    "formera-backend" = {
      image = "localhost.local/formera-backend:latest";
      imageFile = formeraBackendImage;
      labels."io.containers.autoupdate" = lib.mkForce "local";
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
      ports = [ "127.0.0.1:${toString privateBackendPort}:8080/tcp" ];
      log-driver = "journald";
    };

    "formera-frontend" = {
      image = "ghcr.io/formeraapp/formera-frontend:latest";
      environment = {
        BASE_URL = "https://forms.gapul.net";
        API_URL = "https://forms.gapul.net";
        TZ = "Asia/Tokyo";
      };
      ports = [ "127.0.0.1:${toString privateFrontendPort}:3000/tcp" ];
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
      reverse_proxy @backend 127.0.0.1:${toString backendPort}
      reverse_proxy 127.0.0.1:${toString frontendPort}
    }
  '';
}
