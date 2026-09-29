# iMessage ブリッジの常駐 (launchd) と config の生成。system 側 (nix-darwin) に置く。
#
# ブリッジ本体のビルドと署名は home 側 (nix/home/macmini-imessage.nix) が持つ。
# ここが system 側にある理由は 2 つ:
#
#   1. TCC の同一性。macOS 26 は launchd ジョブの許可を「launchd が spawn した実行
#      ファイル」で判定する。home-manager の launchd.agents は必ず
#      `/bin/sh -c '/bin/wait4path /nix/store && exec …'` で包むので、フルディスク
#      アクセスを見に来るのが /bin/sh になり、署名済みバイナリに付けた許可が効かない
#      (2026-09-29 に実測: 包むと chat.db が EPERM、直接 spawn すると読める)。
#      nix-darwin は serviceConfig.ProgramArguments を書けばそのまま plist に出す。
#   2. 順序。config.yaml にはトークンが要り、それは system 側の sops が置く。
#      home-manager の activation は sops より先に走るので、あちらで作ると導入直後の
#      switch で作られない。ここなら postActivation で sops の後 (mkAfter = 1500 の次)
#      に並べられる。
#
# ジョブは config.yaml が現れるまで待つ (KeepAlive.PathState)。トークンが置かれる前の
# rebuild でも壊れない。
{
  lib,
  pkgs,
  user,
  ...
}:
let
  home = "/Users/${user.username}";
  dataDir = "${home}/.local/share/mautrix-imessage";
  tokenDir = "${home}/.config/mautrix-imessage"; # hosts/macmini.nix の sops が置く
  stable = "${home}/.local/libexec/tcc/mautrix-imessage"; # home 側の tcc-stable-binary が置く
  configFile = "${dataDir}/config.yaml";

  # 足りない項目はブリッジが起動時に同梱の example config から補う。ここに書くのは
  # 既定から変える分だけ。
  settings = {
    homeserver = {
      # homeserver の tailnet アドレス。Synapse は 0.0.0.0:8008 で待っている。
      address = "http://100.127.129.31:8008";
      # 上流の既定は mautrix-wsproxy 経由だが、tailnet で双方向に届くので HTTP 直結。
      websocket_proxy = null;
      domain = "gapul.net";
      software = "standard";
    };
    appservice = {
      # 0.0.0.0 なのは、起動が Tailscale より先に来たときに tailnet アドレスへ bind
      # できず落ちるのを避けるため。外からは ALF (hosts/macmini.nix) と hs_token で守る。
      hostname = "0.0.0.0";
      port = 29332; # nix/homelab/matrix-imessage.nix の登録と対
      database = {
        type = "sqlite3-fk-wal";
        uri = "file:${dataDir}/mautrix-imessage.db?_txlock=immediate";
      };
      id = "imessage";
      bot = {
        username = "imessagebot";
        displayname = "iMessage bridge bot";
      };
      ephemeral_events = true;
      # activation で差し込む。
      as_token = "";
      hs_token = "";
    };
    imessage.platform = "mac";
    bridge = {
      user = "@gapul:gapul.net";
      username_template = "imessage_{{.}}";
      displayname_template = "{{.}} (iMessage)";
      command_prefix = "!im";
      # libheif 無しでビルドしてあるので変換できない (pkgs/mautrix-imessage.nix)。
      convert_heif = false;
    };
    logging = {
      min_level = "info";
      writers = [
        {
          type = "stdout";
          format = "pretty-colored";
        }
      ];
    };
  };
  settingsFile = (pkgs.formats.yaml { }).generate "mautrix-imessage-config.yaml" settings;
in
{
  # sops (mkAfter = 1500) の後。トークンが両方あるときだけ書く。root で走るので
  # 所有者をユーザーに戻す。設定を変えれば plist は変わらないが、このスクリプトが
  # 毎回 config を書き直すので、次の再起動で反映される。
  system.activationScripts.postActivation.text = lib.mkOrder 1600 ''
    if [ -r '${tokenDir}/as_token' ] && [ -r '${tokenDir}/hs_token' ]; then
      /bin/mkdir -p '${dataDir}'
      /usr/sbin/chown ${user.username} '${dataDir}'
      (
        umask 077
        AS_TOKEN="$(cat '${tokenDir}/as_token')" HS_TOKEN="$(cat '${tokenDir}/hs_token')" \
          ${pkgs.yq-go}/bin/yq \
            '.appservice.as_token = strenv(AS_TOKEN) | .appservice.hs_token = strenv(HS_TOKEN)' \
            '${settingsFile}' > '${configFile}.tmp'
      )
      /usr/sbin/chown ${user.username} '${configFile}.tmp'
      /bin/mv '${configFile}.tmp' '${configFile}'
    else
      echo "mautrix-imessage: token files missing under ${tokenDir}; config.yaml not written" >&2
    fi
  '';

  launchd.user.agents.mautrix-imessage.serviceConfig = {
    # 包まずに署名済みバイナリを直接 spawn する。理由は冒頭のコメント。
    # -n: config は上の activation が作る。ブリッジには書き戻させない。
    ProgramArguments = [
      stable
      "-c"
      configFile
      "-n"
    ];
    WorkingDirectory = dataDir;
    KeepAlive.PathState.${configFile} = true;
    # フルディスクアクセスが無い、あるいは chat.db にまだ 1 通も無い (ブリッジは
    # 「未ログイン」として即死する) ときに、既定の 10 秒で回すとログだけが太る。
    ThrottleInterval = 60;
    StandardOutPath = "${dataDir}/bridge.log";
    StandardErrorPath = "${dataDir}/bridge.log";
  };
}
