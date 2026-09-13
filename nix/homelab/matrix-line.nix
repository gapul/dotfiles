# LINE のブリッジ。nixpkgs に services.mautrix-* のモジュールが無いので、
# nixpkgs の mautrix-signal モジュールと同じ形をここに書く。どちらも mautrix-go の
# bridgev2 (mxmain) なので、起動の作法は同一:
#
#   1. Nix の settings から config.yaml を作る (部分的でよい。足りない値は
#      ブリッジが同梱の example config から補う)
#   2. 登録ファイルが無ければ --generate-registration で作る
#   3. 登録ファイルの as_token / hs_token を config.yaml に書き戻す
#
# 登録ファイルは Synapse の app_service_config_files に足す。トークンは実行時に
# 生成されて /var/lib に留まり、store には入らない。
#
# ログインは Matrix 側で @linebot:gapul.net に DM して `login` を送る。LINE の
# Chrome 拡張として振る舞うため、ログインすると Chrome 拡張版 LINE は切断される。
#
# 過去ログはこのブリッジでは取れない。bridgev2 の FetchMessages が直近の数十件しか
# 返さない実装 (上流 pkg/connector/sync.go) で、LINE のサーバーにも古い履歴は無い。
# 深い過去は端末のバックアップから別に取り込む。
{
  config,
  lib,
  pkgs,
  ...
}:
let
  dataDir = "/var/lib/matrix-line";
  registrationFile = "${dataDir}/line-registration.yaml";
  settingsFile = "${dataDir}/config.yaml";
  package = pkgs.callPackage ../pkgs/matrix-line.nix { };
  domain = "gapul.net";

  settings = {
    homeserver = {
      address = "http://127.0.0.1:8008";
      inherit domain;
    };
    appservice = {
      address = "http://127.0.0.1:29340";
      hostname = "127.0.0.1";
      port = 29340;
      id = "line";
      bot = {
        username = "linebot";
        displayname = "LINE Bridge Bot";
      };
      as_token = "";
      hs_token = "";
      username_template = "line_{{.}}";
    };
    database = {
      type = "sqlite3-fk-wal";
      uri = "file:${dataDir}/matrix-line.db?_txlock=immediate";
    };
    bridge = {
      command_prefix = "!line";
      permissions."@gapul:${domain}" = "admin";
    };
    # 他のブリッジ (matrix-bridges.nix) と揃える。ただしこのブリッジは直近しか
    # 返さないので、値を大きくしても取れる量は増えない。
    backfill = {
      enabled = true;
      max_initial_messages = 5000;
      max_catchup_messages = 5000;
    };
    double_puppet = {
      servers = { };
      secrets = { };
    };
    encryption.pickle_key = "";
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
  };
  settingsFileUnsubstituted = (pkgs.formats.json { }).generate "matrix-line-config.json" settings;
in
{
  users.users.matrix-line = {
    isSystemUser = true;
    group = "matrix-line";
    home = dataDir;
  };
  users.groups.matrix-line = { };

  services.matrix-synapse.settings.app_service_config_files = [ registrationFile ];
  systemd.services.matrix-synapse.serviceConfig.SupplementaryGroups = [ "matrix-line" ];

  systemd.services.matrix-line = {
    description = "Matrix-LINE bridge";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ] ++ [ config.services.matrix-synapse.serviceUnit ];
    after = [ "network-online.target" ] ++ [ config.services.matrix-synapse.serviceUnit ];
    # 動画のサムネイルと音声の変換に使う。
    path = [ pkgs.ffmpeg-headless ];

    preStart = ''
      old_umask=$(umask)
      umask 0177
      cp '${settingsFileUnsubstituted}' '${settingsFile}'

      if [ ! -f '${registrationFile}' ]; then
        ${lib.getExe package} \
          --generate-registration \
          --config='${settingsFile}' \
          --registration='${registrationFile}'
      fi
      chmod 640 '${registrationFile}'

      ${lib.getExe pkgs.yq} -s '.[0].appservice.as_token = .[1].as_token
        | .[0].appservice.hs_token = .[1].hs_token
        | .[0]' \
        '${settingsFile}' '${registrationFile}' > '${settingsFile}.tmp'
      mv '${settingsFile}.tmp' '${settingsFile}'
      umask $old_umask
    '';

    serviceConfig = {
      User = "matrix-line";
      Group = "matrix-line";
      StateDirectory = baseNameOf dataDir;
      WorkingDirectory = dataDir;
      ExecStart = "${lib.getExe package} --config='${settingsFile}' --registration='${registrationFile}'";
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
