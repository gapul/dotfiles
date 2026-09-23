# A mautrix-go bridgev2 (mxmain) bridge as a NixOS module, for bridges that
# nixpkgs has no services.mautrix-* module for. Used by matrix-line.nix and
# matrix-bridges-v2.nix.
#
# 起動の作法は nixpkgs の mautrix-signal モジュールと同じ:
#
#   1. Nix の settings から config.yaml を作る (部分的でよい。足りない値は
#      ブリッジが同梱の example config から補う)
#   2. 登録ファイルが無ければ --generate-registration で作る
#   3. 登録ファイルの as_token / hs_token を config.yaml に書き戻す
#
# 登録ファイルは Synapse の app_service_config_files に足す。トークンは実行時に
# 生成されて /var/lib に留まり、store には入らない。
#
# Arguments:
#   name       unit, user, and /var/lib directory name
#   id         appservice id; also derives the bot (<id>bot), command prefix
#              (!<id>) and puppet localparts (<id>_...)
#   title      human-readable network name for unit descriptions
#   package    pkgs -> derivation
#   port       appservice port on localhost; must be unique across bridges
#   network    network-specific settings (the bridge's example-config.yaml)
#   extraPath  pkgs -> runtime tools besides ffmpeg
#   secretsFile / secretsJq
#              for values that must stay out of the store. The file is a
#              root-owned KEY=value env file placed by hand; secretsJq is a jq
#              fragment (starting with "|") that reads it via env.KEY. The bridge
#              does not start until the file exists, so deploys stay green before
#              the secret is placed. Restart <name>-config and <name> after
#              placing or changing it (restartTriggers do not see the file).
{
  name,
  id,
  title,
  package,
  port,
  network ? { },
  extraPath ? _: [ ],
  secretsFile ? null,
  secretsJq ? "",
}:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  dataDir = "/var/lib/${name}";
  registrationFile = "${dataDir}/${id}-registration.yaml";
  settingsFile = "${dataDir}/config.yaml";
  pkg = package pkgs;
  domain = "gapul.net";

  settings = {
    homeserver = {
      address = "http://127.0.0.1:8008";
      inherit domain;
    };
    appservice = {
      address = "http://127.0.0.1:${toString port}";
      hostname = "127.0.0.1";
      inherit port id;
      bot = {
        username = "${id}bot";
        displayname = "${title} Bridge Bot";
      };
      as_token = "";
      hs_token = "";
      username_template = "${id}_{{.}}";
    };
    database = {
      type = "sqlite3-fk-wal";
      uri = "file:${dataDir}/${name}.db?_txlock=immediate";
    };
    bridge = {
      command_prefix = "!${id}";
      permissions."@gapul:${domain}" = "admin";
    };
    # matrix-bridges.nix と揃える。どこまで遡れるかはネットワーク次第。
    backfill = {
      enabled = true;
      max_initial_messages = 5000;
      max_catchup_messages = 5000;
    };
    double_puppet = {
      servers = { };
      secrets = { };
    };
    # 他のブリッジと同じ方針 (matrix-bridges.nix の encryption)。pickle_key は
    # config oneshot が初回に生成して ${dataDir}/pickle_key に置き、毎回差し込む。
    encryption = {
      allow = true;
      default = true;
      require = false;
      msc4190 = true;
      self_sign = true;
      pickle_key = "";
    };
    provisioning.shared_secret = "";
    public_media.signing_key = "";
    direct_media.server_key = "";
    logging = {
      min_level = "info";
      writers = lib.singleton {
        type = "stdout";
        format = "pretty-colored";
        time_format = " ";
      };
    };
  }
  // lib.optionalAttrs (network != { }) { inherit network; };
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

  # config.yaml と登録ファイルは別の oneshot で先に作る。ブリッジ本体の preStart で
  # 作ると、初回のデプロイで Synapse の再起動が登録ファイルより先に来て、存在しない
  # ファイルを読んで Synapse ごと落ちる (2026-09-13 に実際に踏んだ)。
  systemd.services."${name}-config" = {
    description = "Generate the Matrix-${title} bridge config and registration";
    before = [ config.services.matrix-synapse.serviceUnit ];
    wantedBy = [ config.services.matrix-synapse.serviceUnit ];
    requires = [ "matrix-doublepuppet-registration.service" ];
    after = [ "matrix-doublepuppet-registration.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = name;
      Group = name;
      # ダブルパペットのトークンを読むためだけのグループ。本体の unit には付けない。
      SupplementaryGroups = [ "matrix-doublepuppet" ];
      StateDirectory = baseNameOf dataDir;
      WorkingDirectory = dataDir;
    }
    # "-": a missing file is not an error; the bridge unit is gated on it instead.
    // lib.optionalAttrs (secretsFile != null) { EnvironmentFile = "-${secretsFile}"; };
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

      # 作り直すと DB に保存した暗号鍵を復号できなくなるので、無いときだけ作る。
      if [ ! -s '${dataDir}/pickle_key' ]; then
        ${pkgs.openssl}/bin/openssl rand -hex 32 > '${dataDir}/pickle_key'
      fi

      # スマホから自分が送った発言を @gapul として出す (matrix-doublepuppet.nix)。
      PICKLE_KEY="$(cat '${dataDir}/pickle_key')" \
      DOUBLE_PUPPET="as_token:$(cat /var/lib/matrix-doublepuppet/as_token)" \
        ${lib.getExe pkgs.yq} -s '.[0].appservice.as_token = .[1].as_token
        | .[0].appservice.hs_token = .[1].hs_token
        | .[0].double_puppet.secrets["${domain}"] = env.DOUBLE_PUPPET
        | .[0].encryption.pickle_key = env.PICKLE_KEY${secretsJq}
        | .[0]' \
        '${settingsFile}' '${registrationFile}' > '${settingsFile}.tmp'
      mv '${settingsFile}.tmp' '${settingsFile}'
    '';
    restartTriggers = [ settingsFileUnsubstituted ];
  };

  systemd.services.${name} = {
    description = "Matrix-${title} bridge";
    wantedBy = [ "multi-user.target" ];
    requires = [ "${name}-config.service" ];
    wants = [ "network-online.target" ] ++ [ config.services.matrix-synapse.serviceUnit ];
    after = [
      "network-online.target"
      "${name}-config.service"
    ]
    ++ [ config.services.matrix-synapse.serviceUnit ];
    # 動画のサムネイルと音声の変換に使う。
    path = [ pkgs.ffmpeg-headless ] ++ extraPath pkgs;
    unitConfig = lib.optionalAttrs (secretsFile != null) { ConditionPathExists = secretsFile; };

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
