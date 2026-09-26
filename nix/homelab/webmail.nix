# Browser access to mail, calendar, tasks and contacts. Both pieces are clients of
# servers that already run here (Stalwart, Radicale) and hold no data of their own.
#
# - Roundcube (webmail.gapul.net) reads Stalwart over IMAPS 993. Login is the
#   Stalwart account name (gmail / work / school) and its password. nixpkgs'
#   services.roundcube assumes nginx and would fight Caddy for 80/443, so it runs
#   as a container. The DB is SQLite (image default) and only holds sessions and
#   preferences.
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
in
{
  # The image runs Apache as www-data (uid 33) and keeps its SQLite DB in this
  # volume. Owned by root it fails on every request with "unable to open
  # database file" (seen 2026-09-26), so hand the directory to uid 33.
  systemd.tmpfiles.rules = [
    "d /var/lib/homelab/roundcube 0700 33 33 -"
  ];

  virtualisation.oci-containers.containers."roundcube" = {
    image = "docker.io/roundcube/roundcubemail:latest-apache";
    environment = {
      "ROUNDCUBEMAIL_DEFAULT_HOST" = "ssl://mail.gapul.net";
      "ROUNDCUBEMAIL_DEFAULT_PORT" = "993";
      "ROUNDCUBEMAIL_SMTP_SERVER" = "ssl://mail.gapul.net";
      "ROUNDCUBEMAIL_SMTP_PORT" = "465";
      "ROUNDCUBEMAIL_SKIN" = "elastic";
      "ROUNDCUBEMAIL_PLUGINS" = "archive,zipdownload";
    };
    volumes = [
      "/var/lib/homelab/roundcube:/var/roundcube/db:rw"
    ];
    ports = [
      "127.0.0.1:8121:80/tcp"
    ];
    log-driver = "journald";
  };

  systemd.services."podman-roundcube" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
  };

  # The container reaches mail.gapul.net (this host's tailnet address) on 993.
  # Those packets arrive on the podman bridge, which trustedInterfaces = tailscale0
  # does not cover. Bridges are podman0, podman1, ... so use the iptables wildcard.
  networking.firewall.interfaces."podman+".allowedTCPPorts = [ 993 ];

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
