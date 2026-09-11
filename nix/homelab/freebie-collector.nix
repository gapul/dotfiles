{
  lib,
  pkgs,
  ...
}:
let
  collector = ../../configs/homelab/freebie-collector/collector.py;
  sources = ../../configs/homelab/freebie-collector/sources.json;
  stateDir = "/srv/annex/freebie-collector";
  repo = "${stateDir}/assets";
  inbox = "/srv/annex/freebie-inbox";

  runner = pkgs.writeShellApplication {
    name = "freebie-collector-run";
    runtimeInputs = [
      pkgs.git
      pkgs.git-annex
      pkgs.python3
    ];
    text = ''
      export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      export GIT_CONFIG_GLOBAL=/dev/null
      export GIT_CONFIG_SYSTEM=/dev/null

      # A shared clone keeps Git objects and annex content hard-linked to the
      # central bare repository. It is an automation-only, untrusted annex peer.
      if [ ! -d "${repo}/.git" ]; then
        git clone --shared --branch main /srv/annex/assets.git "${repo}"
        git -C "${repo}" annex init "homeserver collector"
        git -C "${repo}" config annex.hardlink true
        git -C "${repo}" annex untrust here
      fi

      git -C "${repo}" config user.name "freebie-collector"
      git -C "${repo}" config user.email "freebie-collector@homeserver.invalid"
      git -C "${repo}" config commit.gpgsign false
      git -C "${repo}" annex sync --no-content

      exec python3 "${collector}" run \
        --config "${sources}" \
        --state "${stateDir}/state" \
        --repo "${repo}" \
        --inbox "${inbox}"
    '';
  };
in
{
  systemd.tmpfiles.rules = [
    "d ${stateDir} 0700 gapul users -"
    "d ${inbox} 0700 gapul users -"
  ];

  systemd.services.freebie-collector = {
    description = "Discover and archive limited-time free digital assets";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "gapul";
      Group = "users";
      ExecStart = lib.getExe runner;
      UMask = "0077";
      Nice = 10;
      IOSchedulingClass = "idle";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "/srv/annex" ];
    };
  };

  systemd.timers.freebie-collector = {
    description = "Run the limited-time free asset collector twice daily";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = [
        "*-*-* 08:15:00"
        "*-*-* 20:15:00"
      ];
      Persistent = true;
      RandomizedDelaySec = "10m";
      Unit = "freebie-collector.service";
    };
  };
}
