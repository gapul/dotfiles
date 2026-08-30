# Matrix のブリッジ。第1陣は資格情報を外から用意しなくてよいものだけ。
#
# Conduit のままだったら、この形では書けなかった。appservice の登録が RocksDB の
# 中にあって admin room からしか変えられなかったので、コンテナに config.yaml を
# 手置きするしかなかった。Synapse に替えて登録が設定ファイルになったので、
# nixpkgs の services.mautrix-* がそのまま使える (#516 参照)。
#
# registerToSynapse が既定で true。登録ファイルを生成して
# services.matrix-synapse.settings.app_service_config_files に足すところまで
# モジュールがやる。ここで書くのは「誰がどこに繋ぐか」だけでよい。
#
# ここに入れていないもの:
#   telegram  — api_id / api_hash が要る。nix の settings に書くと store が
#               誰でも読めるので、sops から environmentFile で渡す形にしてから足す。
#   twitter / linkedin / gmessages / slack / line / imessage
#             — モジュールが無い。パッケージがあるもの (gmessages, slack) は
#               自前の unit、残りはコンテナ。第2陣以降。
#   teams     — 個人の teams.live.com 向けの実験的な実装しか無い。会社テナントは
#               Azure のアプリ登録が要るので、そもそも許可の話になる。
#   simplex   — 構造的に無理。あの設計は識別子を持たないことが核心で、
#               puppeting が必要とする安定した ID が存在しない。
{ ... }:
let
  # Synapse は同じ箱の 8008 で待っている。ブリッジもホスト側の unit なので localhost でよい。
  address = "http://127.0.0.1:8008";
  domain = "gapul.net";
  admin = "@gapul:${domain}";

  # 既定は permissions = { "*" = "relay" } で、誰でも relay として使える。
  # 自分ひとりの箱なので閉じる。
  permissions = {
    ${admin} = "admin";
  };

  homeserver = {
    inherit address domain;
  };
in
{
  # mautrix のブリッジは libolm に依存する。libolm は Matrix 財団が 2024 年に非推奨
  # にしたもので、nixpkgs も insecure の印を付けている。
  #
  # 承知のうえで許可する。理由:
  #   - この libolm が使われるのは「ブリッジ側の E2EE」だけで、ここでは有効にして
  #     いない。ブリッジと Synapse は同じ箱の localhost で話し、暗号化の境界は
  #     相手のネットワーク側 (Discord や Meta) にある。そこは向こうが平文で見ている。
  #   - 逃げ道は 2 つあったがどちらも通らない。goolm (純 Go 実装) は signal / meta /
  #     slack / gmessages には withGoolm フラグがあるが、mautrix-discord のパッケージ
  #     は 0.7.7 と古くフラグが無い。つまり discord のためにどのみち許可が要る。
  #     3 本だけ実験的な実装 (上流は「本番では勧めない」と書いている) に替えても、
  #     許可リストは開いたままで、揃わないぶん読みにくくなるだけ。
  #
  # **E2EE を有効にするときは、この判断をやり直すこと。** そのときは libolm が実際に
  # 使われる側に回るので、goolm かコンテナかを選び直す必要がある。
  nixpkgs.config.permittedInsecurePackages = [ "olm-3.2.16" ];

  services.mautrix-discord = {
    enable = true;
    registerToSynapse = true;
    settings = {
      inherit homeserver;
      appservice = {
        id = "discord";
        port = 29334;
        bot.username = "discordbot";
      };
      bridge = { inherit permissions; };
    };
  };

  services.mautrix-signal = {
    enable = true;
    registerToSynapse = true;
    settings = {
      inherit homeserver;
      bridge = { inherit permissions; };
    };
  };

  # Instagram と Messenger は同じ mautrix-meta の別インスタンス。network.mode で
  # 分かれる。ポートと appservice.id と bot の名前は必ずずらすこと (揃えると
  # 片方の登録がもう片方を上書きして、後から入れた方しか動かない)。
  services.mautrix-meta.instances = {
    instagram = {
      enable = true;
      registerToSynapse = true;
      settings = {
        inherit homeserver;
        network.mode = "instagram";
        appservice = {
          id = "instagram";
          port = 29320;
          bot.username = "instagrambot";
        };
        bridge = { inherit permissions; };
      };
    };

    messenger = {
      enable = true;
      registerToSynapse = true;
      settings = {
        inherit homeserver;
        network.mode = "messenger";
        appservice = {
          id = "messenger";
          port = 29321;
          bot.username = "messengerbot";
        };
        bridge = { inherit permissions; };
      };
    };
  };
}
