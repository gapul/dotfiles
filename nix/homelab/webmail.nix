# Browser access to mail, calendar, tasks and contacts. Both pieces are clients of
# servers that already run here (Stalwart, Radicale) and hold no data of their own.
#
# - Twake Mail (webmail.gapul.net, linagora/tmail-web) is a static Flutter web build that
#   talks JMAP to Stalwart straight from the browser. The container only serves files
#   (nginx); login is the Stalwart account name (gmail / sean / school) and its password,
#   sent as Basic auth to mail.gapul.net. That is cross-origin, so it depends on
#   http.permissive-cors and on http.url advertising the public https URL in the JMAP
#   session (both in homelab/mail.nix). Replaced Roundcube on 2026-10-22 to drop PHP.
# - InfCloud (dav.gapul.net/infcloud/) is a static HTML/JS CalDAV/CardDAV client.
#   Serving it under the Radicale vhost makes it same-origin, so no CORS has to be
#   faked in Caddy. Login is the Radicale credentials.
#
# Sending goes through Stalwart's submissions listener (mail.gapul.net:465) with the
# same login; Stalwart relays it out through the Google account behind that mailbox
# (homelab/mail.nix), so only that account's own address works as From.
{
  lib,
  pkgs,
  ...
}:
let
  infcloud = pkgs.stdenvNoCC.mkDerivation {
    pname = "infcloud";
    version = "0.13.1";
    src = pkgs.fetchzip {
      url = "https://www.inf-it.com/InfCloud_0.13.1.zip";
      hash = "sha256-OEZV1KWYua4HCVqtUMoPr1Y7a0DiO+2Lgy4tIBnQULo=";
    };
    # config.js ships with a Davical example active; a later `var` assignment
    # wins, so appending is enough. href is the server root: InfCloud resolves
    # the principal (/gapul/) through current-user-principal. settingsAccount
    # is where UI preferences get PROPPATCHed.
    installPhase = ''
      cp -r . $out
      chmod u+w $out/config.js
      sed -i "s/^var globalInterfaceLanguage='en_US';/var globalInterfaceLanguage='ja_JP';/" $out/config.js
      cat >> $out/config.js <<'CFG'
      var globalNetworkCheckSettings={href: 'https://dav.gapul.net/', timeOut: 15000, lockTimeOut: 10000, checkContentType: true, settingsAccount: true, delegation: false, additionalResources: [], hrefLabel: null, forceReadOnly: null, ignoreAlarms: false, backgroundCalendars: []};
      CFG
    '';
  };
  # The app reads this at startup in the browser. Everything Google/Linagora-specific
  # (push via FCM, the Twake app grid, Sentry) is off. DOMAIN_REDIRECT_URL only matters
  # if the login page ends up on an OIDC flow.
  twakeEnv = pkgs.writeText "tmail-env.file" ''
    SERVER_URL=https://mail.gapul.net/
    DOMAIN_REDIRECT_URL=https://webmail.gapul.net
    WEB_OIDC_CLIENT_ID=teammail-web
    OIDC_SCOPES=openid,profile,email,offline_access
    APP_GRID_AVAILABLE=unsupported
    FCM_AVAILABLE=unsupported
    IOS_FCM=unsupported
    FORWARD_WARNING_MESSAGE=
    PLATFORM=other
    WS_ECHO_PING=
    COZY_INTEGRATION=
    COZY_EXTERNAL_BRIDGE_VERSION=
    SENTRY_ENABLED=false
    SENTRY_DSN=
    SENTRY_ENVIRONMENT=
    FORCE_EMAIL_QUERY=false
  '';
in
{
  virtualisation.oci-containers.containers."twake-mail" = {
    image = "docker.io/linagora/tmail-web:latest";
    volumes = [
      "${twakeEnv}:/usr/share/nginx/html/assets/env.file:ro"
    ];
    ports = [
      "127.0.0.1:8121:80/tcp"
    ];
    log-driver = "journald";
  };

  systemd.services."podman-twake-mail" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
  };

  # The dav vhost itself (tls / reverse_proxy) comes from the sites table in
  # hosts/homeserver.nix. Caddy evaluates handle_path before reverse_proxy in its
  # directive order, and file_server ends the chain when it answers, so only
  # /infcloud/ stops here.
  services.caddy.virtualHosts."dav.gapul.net".extraConfig = ''
    handle_path /infcloud/* {
      root * ${infcloud}
      file_server
    }
  '';
}
