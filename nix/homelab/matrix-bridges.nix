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
#   telegram / slack / gmessages
#             — nixpkgs にモジュールが無い (telegram は古い Python 版しか無い)。
#               matrix-bridges-v2.nix に mk-matrix-bridgev2.nix で書いた。
#   twitter / linkedin / imessage
#             — モジュールが無い。imessage は macmini 側 (home/macmini-imessage.nix)。
#   line      — モジュールもパッケージも無いので、両方を自前で書いた (matrix-line.nix)。
#   teams     — 個人の teams.live.com 向けの実験的な実装しか無い。会社テナントは
#               Azure のアプリ登録が要るので、そもそも許可の話になる。
#   simplex   — 構造的に無理。あの設計は識別子を持たないことが核心で、
#               puppeting が必要とする安定した ID が存在しない。
_:
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

  # 過去ログの取り込み。ここは**ログインする前に**決めておく必要がある。
  #
  # 深く取れるのはポータルが初めて作られる一度きり。既定は 50 件で、後から遡るには
  # 「backfill queue」が要るが、上流の設定にこう書いてある:
  #
  #   Settings for the backwards backfill queue. This only applies when connecting to
  #   Beeper as standard Matrix servers don't support inserting messages into history.
  #
  # 素の Synapse は履歴の途中に差し込めない (MSC2716 が廃止された)。空の部屋へ
  # 順に流し込む初回だけは効くので、そこで取れるだけ取る。既定のまま入ると、
  # あとからやり直すには部屋を消すことになる。
  #
  # どれだけ取れるかは相手次第で、こちらの設定では決まらない:
  #   Telegram / Discord — サーバ側に履歴がある。いちばん深く取れる
  #   Meta / LinkedIn / Slack — サーバ側にある
  #   Signal — 端末にしか無い。連携後のぶんが中心で、過去は基本的に取れない
  # ブリッジ側の暗号化 (end-to-bridge encryption)。
  #
  # Element / Element X は新しい DM を暗号化で作るので、これが無いとブリッジの
  # ボットとの DM でコマンドが届かない (2026-09-13 に LINE の login が
  # "this bridge has not been configured to support encryption" で弾かれた)。
  #
  #   allow/default — 暗号化されたルームでも動き、自分で作るポータルも暗号化する
  #   require = false — 暗号化されていないルームも拒否しない (既存の管理用ルーム等)
  #   self_sign — Element X は未検証の端末に鍵を渡さないので、ブリッジが自分の端末を
  #               クロス署名する。これが無いと Element X から送った発言が読めない
  #   msc4190 — appservice が自分の端末を管理する方式。Synapse 1.141 以降は
  #             実験機能フラグ無しで使える (今は 1.159)
  #
  # pickle_key (ブリッジの DB に鍵を保存するときの鍵) は matrix-bridge-secrets.nix が
  # host ごとに生成する。mautrix-meta だけは nixpkgs の既定の固定値のまま: 既に
  # 暗号化が有効で DB に鍵が入っているので、変えると復号できなくなる。
  encryption = {
    allow = true;
    default = true;
    require = false;
    msc4190 = true;
    self_sign = true;
  };

  backfill = {
    enabled = true;
    # 5000 は「取りたいだけ取る」と「初回同期が終わる」の折り合い。上流も
    # 「高くすると全部取得してから流し始めるので時間がかかる」と書いている。
    max_initial_messages = 5000;
    max_catchup_messages = 5000;
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
  #
  # 2026-09-14 追記: ブリッジ側の暗号化を有効にしたので、libolm は実際に使われる側に
  # 回った。判断をやり直した結果、許可を続ける:
  #   - libolm の既知の問題はタイミングのサイドチャネルで、観測するには暗号処理の
  #     時間を測れる位置にいる必要がある。ブリッジと Synapse は同じ箱の localhost で
  #     話し、その箱に入れる時点で DB の平文も読める。守る境界が変わらない
  #   - goolm は上流が本番に勧めておらず、mautrix-discord 0.7.7 には選択肢自体が無い
  nixpkgs.config.permittedInsecurePackages = [ "olm-3.2.16" ];

  # Double puppeting for the three nixpkgs-module bridges: the env files come from
  # matrix-bridge-secrets.nix, the modules envsubst "$DOUBLE_PUPPET_SECRET" into the config.
  # Without it the bridges only invite @gapul to portals and the personal space, and own
  # messages sent from the phone show up relayed by the bot.
  services.mautrix-discord = {
    enable = true;
    registerToSynapse = true;
    environmentFile = "/var/lib/matrix-bridge-secrets/discord.env";
    settings = {
      inherit homeserver;
      appservice = {
        id = "discord";
        port = 29334;
        bot.username = "discordbot";
        # nixpkgs の mautrix-discord は 0.7.7 で、bridgev2 より前の設定の形。
        # DB は top-level の database ではなく appservice.database に置く。
        # signal や meta はモジュール側が既定を持っているが、discord の settings の
        # 既定は {} なので自分で書かないと "appservice.database not configured"
        # で起動を繰り返す (2026-08-31 に実際に踏んだ)。
        database = {
          type = "sqlite3-fk-wal";
          uri = "file:/var/lib/mautrix-discord/mautrix-discord.db?_txlock=immediate";
        };
      };
      bridge = {
        inherit permissions;
        # mautrix-discord is still a v1 bridge: the key is login_shared_secret_map here.
        login_shared_secret_map.${domain} = "$DOUBLE_PUPPET_SECRET";
        # 旧形式の設定なので encryption も bridge の下。self_sign はこの版に無く、
        # pickle_key も持たない (旧ブリッジは固定値を使う)。
        encryption = {
          inherit (encryption)
            allow
            default
            require
            msc4190
            ;
        };
        # discord は 0.7.7 なので backfill の書き方も旧形式。bridgev2 の
        # max_initial_messages ではなく、DM / チャンネル / スレッドを個別に指定する。
        #
        # チャンネルを DM と同じ深さにしない。ギルドのチャンネルは桁が違うので、
        # 全部を初回に取りに行くと同期が終わらない (上流も「高くすると全部取得して
        # から流し始めるので時間がかかる」と書いている)。
        backfill = {
          forward_limits = {
            initial = {
              dm = 5000;
              channel = 1000;
              thread = 500;
            };
            # -1 は「最後に橋渡ししたメッセージ以降を全部」。DM は取りこぼしたくない
            # ので無制限、チャンネルは上限を置く。
            missed = {
              dm = -1;
              channel = 1000;
              thread = 500;
            };
          };
        };
      };
    };
  };

  services.mautrix-signal = {
    enable = true;
    registerToSynapse = true;
    environmentFile = "/var/lib/matrix-bridge-secrets/signal.env";
    settings = {
      inherit homeserver backfill;
      encryption = encryption // {
        pickle_key = "$ENCRYPTION_PICKLE_KEY";
      };
      double_puppet.secrets.${domain} = "$DOUBLE_PUPPET_SECRET";
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
      environmentFile = "/var/lib/matrix-bridge-secrets/instagram.env";
      settings = {
        inherit homeserver;
        inherit backfill encryption;
        double_puppet.secrets.${domain} = "$DOUBLE_PUPPET_SECRET";
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
      environmentFile = "/var/lib/matrix-bridge-secrets/messenger.env";
      settings = {
        inherit homeserver;
        inherit backfill encryption;
        double_puppet.secrets.${domain} = "$DOUBLE_PUPPET_SECRET";
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
