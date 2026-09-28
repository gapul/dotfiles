# iMessage を Matrix に繋ぐ。macmini でしかできないブリッジ。
#
# 他のブリッジ (discord / signal / meta) は homeserver に置いてある。これだけ
# こちらにあるのは、iMessage に外から叩ける API が無いため。ブリッジは
# ~/Library/Messages/chat.db を読み、送信は Messages.app を動かして行う。つまり
# 「iMessage にログイン済みの Mac」そのものが接続の実体で、Linux には置けない。
#
# ## Synapse との繋がり
#
# appservice なので双方向に届く必要がある。homeserver の Synapse は 0.0.0.0:8008 で
# 待っていて tailnet から入れる。こちら側の受け口も tailnet アドレスで公開するので、
# wsproxy (上流が NAT 越えのために用意しているもの) は要らない。
#
# 登録ファイルは homeserver 側の Synapse が読む必要がある。機械が別なので、他の
# ブリッジのように services.mautrix-* が両側を面倒みてくれる構成にはならない。代わりに
# as_token / hs_token を secrets/matrix-imessage.yaml に置き、homeserver は登録ファイル
# (nix/homelab/matrix-imessage.nix)、こちらは config.yaml に、同じ値を差し込む。
# トークンのファイルは hosts/macmini.nix の sops が ~/.config/mautrix-imessage/ に置く
# (host 鍵で開けるのは system 側だけなので、home-manager からは触れない)。
#
# config.yaml は launchd がブリッジを上げるたびに、起動ラッパーが下の設定とトークンから
# 作り直す。activation でやらないのは順序の問題: nix-darwin では home-manager の
# activation が sops より先に走るので、トークンを初めて入れた switch では「まだ無い」
# で終わり、もう一度 switch するまで動かなかった。起動時に作れば sops が置いた次の
# 周回で拾えるし、設定を変えれば plist が変わって再起動され、その場で反映される。
# ブリッジ自身にも config を書き戻す機能があるが、-n で止めてある。正は Nix 側。
#
# ## Synapse 側の暗号化
#
# encryption は入れていない。このブリッジは bridge.user 固定で、着信があれば portal が
# 勝手にできる (ログインの命令が要らない) ので、bot との DM を使う場面がほぼ無い。
# Element X は新しい DM を暗号化で作るので、bot に命令を送るときは暗号化を切って
# 部屋を作ること。
#
# ## フルディスクアクセス
#
# chat.db は TCC で守られているので、許可が要る。store のパスを直接 launchd に
# 書くと、ブリッジを更新するたびに別物と見なされて許可が切れる。sunshine と同じく
# 自己署名の identity で署名して ~/.local/libexec/tcc/ に置き、そこを指す。
# 署名の要件式から cdhash が落ちるので、中身が変わっても同じものとして扱われる。
#
# 許可の付与そのものは一度だけ人の手が要る (システム設定 > プライバシーとセキュリティ
# > フルディスクアクセス に ~/.local/libexec/tcc/mautrix-imessage を足す)。
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # olm は insecure の印が付いている。homeserver 側 (nix/homelab/matrix-bridges.nix) と
  # 同じ判断で許可する: 使われるのはブリッジ側の E2EE だけで、そこは有効にしていない。
  # ここで nixpkgs を import し直すのは、home-manager から host の nixpkgs.config に
  # 手が届かないため。E2EE を入れるときは両方まとめて判断し直すこと。
  pkgsWithOlm = import pkgs.path {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.permittedInsecurePackages = [ "olm-3.2.16" ];
  };
  bridge = pkgsWithOlm.callPackage ../pkgs/mautrix-imessage.nix { };
  dataDir = "${config.home.homeDirectory}/.local/share/mautrix-imessage";
  stable = "${config.home.homeDirectory}/.local/libexec/tcc/mautrix-imessage";
  tokenDir = "${config.home.homeDirectory}/.config/mautrix-imessage";

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

  # 起動ラッパー。トークンを差し込んだ config.yaml を書いてからブリッジに exec する。
  # exec なので TCC が見るのは署名済みの安定バイナリのまま (home-manager 自体も
  # /bin/sh -c 'wait4path && exec ...' で包んでいるので、前から同じ形)。
  start = pkgs.writeShellScript "mautrix-imessage-start" ''
    set -euo pipefail
    umask 077
    /bin/mkdir -p '${dataDir}'
    AS_TOKEN="$(cat '${tokenDir}/as_token')" HS_TOKEN="$(cat '${tokenDir}/hs_token')" \
      ${pkgs.yq-go}/bin/yq \
        '.appservice.as_token = strenv(AS_TOKEN) | .appservice.hs_token = strenv(HS_TOKEN)' \
        '${settingsFile}' > '${dataDir}/config.yaml.tmp'
    /bin/mv '${dataDir}/config.yaml.tmp' '${dataDir}/config.yaml'
    exec '${stable}' -c '${dataDir}/config.yaml' -n
  '';
in
{
  home.activation.tccStableIMessage = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${../../configs/bin/tcc-stable-binary} \
      ${bridge}/bin/mautrix-imessage mautrix-imessage || true
  '';

  launchd.agents.mautrix-imessage = {
    enable = true;
    config = {
      # ラッパー経由で、署名済みの安定した場所のバイナリに exec する。理由は上の activation を参照。
      ProgramArguments = [ "${start}" ];
      WorkingDirectory = dataDir;
      # Do not start until sops has placed the tokens (hosts/macmini.nix). Until then, do
      # not crash-loop; launchd watches the path and starts the bridge as soon as the file
      # appears. The token files are symlinks into /run/secrets; PathState follows them.
      KeepAlive.PathState."${tokenDir}/hs_token" = true;
      # フルディスクアクセスが無いとブリッジは chat.db を開けずに即死する。既定の 10 秒で
      # 回すとログだけが太るので、間隔を空ける。許可を足せば次の周回で上がる。
      ThrottleInterval = 60;
      StandardOutPath = "${dataDir}/bridge.log";
      StandardErrorPath = "${dataDir}/bridge.log";
    };
  };
}
