# Element Web (element.gapul.net), the browser client for the Synapse in matrix.nix.
#
# Element X has no desktop or web build (the rust-sdk based "Element X Web" is still an
# experiment upstream), so this is the way to use Matrix from a browser without
# app.element.io. It is static HTML/JS and holds no data here: sessions and keys live
# in the browser, everything else on Synapse. Login is the Matrix account itself, so
# no Authelia in front (same as webmail).
#
# Not in the `sites` table in hosts/homeserver.nix because there is no upstream to
# proxy to or probe. The vhost still needs its own A record in Cloudflare pointing at
# this host's tailnet address, like the others.
{ config, pkgs, ... }:
let
  certDir = config.security.acme.certs."gapul.net".directory;
  element = pkgs.element-web.override {
    conf = {
      default_server_config."m.homeserver" = {
        base_url = "https://matrix.gapul.net";
        server_name = "gapul.net";
      };
      # Single-user server: no point offering other homeservers or guest access.
      disable_custom_urls = true;
      disable_guests = true;
      show_labs_settings = true;
    };
  };
in
{
  services.caddy.virtualHosts."element.gapul.net".extraConfig = ''
    tls ${certDir}/cert.pem ${certDir}/key.pem
    # Headers Element's docs ask for when self-hosting (clickjacking protection).
    header {
      X-Frame-Options SAMEORIGIN
      X-Content-Type-Options nosniff
      X-XSS-Protection "1; mode=block"
      Content-Security-Policy "frame-ancestors 'self'"
    }
    root * ${element}
    file_server
  '';
}
