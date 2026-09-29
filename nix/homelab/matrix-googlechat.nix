# Google Chat bridge (mautrix-googlechat). nixpkgs has the package but no module.
#
# This is the Python generation of mautrix (like nixpkgs' legacy mautrix-telegram
# module), not bridgev2, so the config keys differ from mk-matrix-bridgev2.nix:
# the database lives under appservice, encryption and backfill under bridge, and
# double puppeting is bridge.login_shared_secret_map. The unit layout is the same
# as the bridgev2 helper: a config oneshot first (so Synapse never restarts before
# the registration file exists), then the bridge itself.
#
# Log in by DMing @googlechatbot:gapul.net and sending `login`, then pasting the
# chat.google.com cookies it asks for.
#
# Port 29319: upstream's default (29320) is taken by instagram here.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  name = "mautrix-googlechat";
  id = "googlechat";
  dataDir = "/var/lib/${name}";
  registrationFile = "${dataDir}/${id}-registration.yaml";
  settingsFile = "${dataDir}/config.yaml";
  # nixpkgs builds it against the default python (3.14), where it dies on import:
  # `import cgi` (removed in 3.13) and an enum auto() ordering change, and aiohttp
  # no longer pulls in async_timeout. Upstream has had 3 commits since v0.5.2
  # (2025-07) and fixes none of this, so build it on 3.12 and add the missing
  # dependency. Checked 2026-09-29 on homeserver: --generate-registration and a
  # dry start both get as far as talking to Synapse.
  pkg = (pkgs.mautrix-googlechat.override { python3 = pkgs.python312; }).overridePythonAttrs (o: {
    propagatedBuildInputs = o.propagatedBuildInputs ++ [ pkgs.python312Packages.async-timeout ];
  });
  domain = "gapul.net";
  port = 29319;

  settings = {
    homeserver = {
      address = "http://127.0.0.1:8008";
      inherit domain;
      software = "standard";
    };
    appservice = {
      address = "http://127.0.0.1:${toString port}";
      hostname = "127.0.0.1";
      inherit port id;
      database = "sqlite:///${dataDir}/${name}.db";
      bot_username = "${id}bot";
      bot_displayname = "Google Chat Bridge Bot";
      as_token = "";
      hs_token = "";
    };
    bridge = {
      username_template = "${id}_{userid}";
      command_prefix = "!gc";
      permissions."@gapul:${domain}" = "admin";
      # Double puppeting via the appservice token (matrix-doublepuppet.nix).
      login_shared_secret_map.${domain} = "";
      # Same policy as the other bridges (matrix-bridges.nix). The Python bridge
      # has no self_sign / msc4190; `appservice = false` means it receives
      # encryption data over /sync, which needs no Synapse experimental flags.
      encryption = {
        allow = true;
        default = false;
        appservice = false;
        require = false;
      };
      # Match the 5000-message policy in matrix-bridges.nix for plain chats;
      # threads keep upstream's per-thread limits.
      backfill = {
        initial_thread_limit = 50;
        initial_thread_reply_limit = 500;
        initial_nonthread_limit = 5000;
        missed_event_limit = 5000;
      };
      provisioning.shared_secret = "disable";
    };
    logging = {
      version = 1;
      formatters.precise.format = "[%(levelname)s@%(name)s] %(message)s";
      handlers.console = {
        class = "logging.StreamHandler";
        formatter = "precise";
      };
      loggers = {
        mau.level = "INFO";
        maugclib.level = "INFO";
        aiohttp.level = "INFO";
      };
      root = {
        level = "INFO";
        handlers = [ "console" ];
      };
    };
  };
  settingsFileUnsubstituted = (pkgs.formats.json { }).generate "${name}-config.json" settings;
in
{
  users.users.${name} = {
    isSystemUser = true;
    group = name;
    home = dataDir;
  };
  users.groups.${name} = { };

  services.matrix-synapse.settings.app_service_config_files = [ registrationFile ];
  systemd.services.matrix-synapse.serviceConfig.SupplementaryGroups = [ name ];

  systemd.services."${name}-config" = {
    description = "Generate the Matrix-Google Chat bridge config and registration";
    before = [ config.services.matrix-synapse.serviceUnit ];
    wantedBy = [ config.services.matrix-synapse.serviceUnit ];
    requires = [ "matrix-doublepuppet-registration.service" ];
    after = [ "matrix-doublepuppet-registration.service" ];
    environment.HOME = dataDir;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = name;
      Group = name;
      SupplementaryGroups = [ "matrix-doublepuppet" ];
      StateDirectory = baseNameOf dataDir;
      WorkingDirectory = dataDir;
    };
    script = ''
      umask 0177
      cp '${settingsFileUnsubstituted}' '${settingsFile}'

      if [ ! -f '${registrationFile}' ]; then
        ${lib.getExe pkg} \
          --generate-registration \
          --config='${settingsFile}' \
          --registration='${registrationFile}'
      fi
      chmod 640 '${registrationFile}'

      DOUBLE_PUPPET="as_token:$(cat /var/lib/matrix-doublepuppet/as_token)" \
        ${lib.getExe pkgs.yq} -s '.[0].appservice.as_token = .[1].as_token
        | .[0].appservice.hs_token = .[1].hs_token
        | .[0].bridge.login_shared_secret_map["${domain}"] = env.DOUBLE_PUPPET
        | .[0]' \
        '${settingsFile}' '${registrationFile}' > '${settingsFile}.tmp'
      mv '${settingsFile}.tmp' '${settingsFile}'
    '';
    restartTriggers = [ settingsFileUnsubstituted ];
  };

  systemd.services.${name} = {
    description = "Matrix-Google Chat bridge";
    wantedBy = [ "multi-user.target" ];
    requires = [ "${name}-config.service" ];
    wants = [
      "network-online.target"
      config.services.matrix-synapse.serviceUnit
    ];
    after = [
      "network-online.target"
      "${name}-config.service"
      config.services.matrix-synapse.serviceUnit
    ];
    path = [ pkgs.ffmpeg-headless ];
    # pathlib.Path.home() is called at import time and fails without HOME.
    environment.HOME = dataDir;

    serviceConfig = {
      User = name;
      Group = name;
      StateDirectory = baseNameOf dataDir;
      WorkingDirectory = dataDir;
      ExecStart = "${lib.getExe pkg} --config='${settingsFile}' --registration='${registrationFile}'";
      LockPersonality = true;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      PrivateUsers = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectSystem = "strict";
      Restart = "on-failure";
      RestartSec = "30s";
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      SystemCallArchitectures = "native";
      SystemCallErrorNumber = "EPERM";
      SystemCallFilter = [ "@system-service" ];
      UMask = "0027";
    };
    restartTriggers = [ settingsFileUnsubstituted ];
  };
}
