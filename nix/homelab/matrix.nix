# Matrix の homeserver。2026-08-31 に Conduit から Synapse へ替えた。
#
# なぜ替えたか。ブリッジを Discord/Telegram の 2 本から 10 本規模に増やすことにしたが、
# Conduit はその規模を載せる場所として向いていない:
#
#   - Conduit 本家は止まっている。系譜は Conduit -> conduwuit (アーカイブ) ->
#     continuwuity で、動いていたのは 0.10.12。しかも 2026 年中頃の continuwuity で
#     「暗号化ブリッジが起動できない」「指定した localpart でユーザーが作られず
#     mautrix-telegram が落ちる」が修正されている。まさに踏みに行く場所だった。
#   - continuwuity への載せ替えも素直ではない。RocksDB のスキーマが分岐後で、
#     移行は一方通行。
#   - 決め手は登録方式。Conduit は appservice の登録を RocksDB に持ち admin room 経由
#     でしか変えられない。だからこのファイルは以前「ブリッジは宣言できない」と書いて
#     コンテナのまま置いていた。Synapse は登録を設定ファイルで読むので、そこが解ける。
#     実際 nixpkgs の services.mautrix-* モジュールが使えるようになる。
#
# 移行のコストはゼロだった。まだ誰も使っていない (RocksDB は 4MB、部屋も履歴も無い)。
# 使い始めてからでは同じ判断はできないので、ここで替える。
#
# server_name は gapul.net のまま。well-known (gapul.net/.well-known/matrix/server ->
# matrix.gapul.net:443) と Cloudflare の CNAME が既にそれで通っているので触らない。
{
  config,
  lib,
  pkgs,
  ...
}:
{
  services.matrix-synapse = {
    enable = true;

    settings = {
      server_name = "gapul.net";
      public_baseurl = "https://matrix.gapul.net/";

      # federation はここだけを通る。cloudflared が
      # matrix.gapul.net -> 127.0.0.1:8008 で渡してくる。
      #
      # 0.0.0.0 で待つのは、ブリッジが podman のネットワーク側から叩きに来るため。
      # Conduit のときと露出範囲は同じ (下でファイアウォールに 8008 を開ける)。
      listeners = [
        {
          port = 8008;
          bind_addresses = [ "0.0.0.0" ];
          type = "http";
          tls = false;
          # cloudflared が前段にいるので、送信元は X-Forwarded-For を見る。
          x_forwarded = true;
          resources = [
            {
              names = [
                "client"
                "federation"
              ];
              compress = false;
            }
          ];
        }
      ];

      enable_registration = false;
      # 招待なしで誰でも作れる状態にはしない。ユーザーは register_new_matrix_user で作る。
      registration_shared_secret_path = "/var/lib/secrets/synapse-registration-secret";

      database = {
        name = "psycopg2";
        args = {
          # UNIX ソケット越しに繋ぐので host は書かない。peer 認証で通る。
          database = "matrix-synapse";
          user = "matrix-synapse";
          cp_min = 5;
          cp_max = 10;
        };
      };

      # 自分ひとりの箱なので、部屋の作成やメディアの取得は緩めでよい。
      # ブリッジは大量のイベントを短時間に流すので、既定のレート制限だと詰まる。
      rc_message = {
        per_second = 100;
        burst_count = 500;
      };
      rc_joins.local = {
        per_second = 100;
        burst_count = 500;
      };
      # ブリッジの bot がユーザーを次々作るので、ここも緩めないと初回同期で止まる。
      rc_registration = {
        per_second = 100;
        burst_count = 500;
      };

      trusted_key_servers = [ { server_name = "matrix.org"; } ];
      suppress_key_server_warning = true;

      max_upload_size = "50M";
    };
  };

  # 登録用の共有秘密。enable_registration = false なので外からは作れないが、
  # register_new_matrix_user で自分のアカウントを作るのにこれが要る。ファイルが
  # 無いと Synapse は起動しないので、無ければ作る。中身は一度作ったら変えない
  # (変えると既に配った招待が通らなくなる)。
  systemd.services.matrix-synapse-registration-secret = {
    description = "Synapse の登録共有秘密を用意する";
    wantedBy = [ "matrix-synapse.service" ];
    before = [ "matrix-synapse.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.openssl ];
    script = ''
      f=/var/lib/secrets/synapse-registration-secret
      install -d -m 0755 /var/lib/secrets
      if [ ! -s "$f" ]; then
        openssl rand -hex 32 > "$f"
        chmod 0400 "$f"
      fi
      chown matrix-synapse "$f" || true
    '';
  };

  # Synapse は照合順序に厳しい。C 以外で作られた DB を見つけると起動を拒否する
  # (allow_unsafe_locale で黙らせることはできるが、後で検索がおかしくなる)。
  #
  # このクラスタは atuin が services.atuin の database.createLocally = true で
  # 生やしたもので、既定の照合順序は ja_JP.UTF-8。だから ensureDatabases では
  # 作れない。initialScript もクラスタの初回作成時にしか走らないので使えない。
  # 自分で作る。冪等なので毎回走ってよい。
  systemd.services.matrix-synapse-db-init = {
    description = "Synapse の DB を C ロケールで用意する";
    wantedBy = [ "matrix-synapse.service" ];
    before = [ "matrix-synapse.service" ];
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "postgres";
    };
    path = [ config.services.postgresql.package ];
    script = ''
      psql -tAc "select 1 from pg_roles where rolname='matrix-synapse'" | grep -q 1 \
        || psql -c "CREATE ROLE \"matrix-synapse\" WITH LOGIN"
      psql -tAc "select 1 from pg_database where datname='matrix-synapse'" | grep -q 1 \
        || psql -c "CREATE DATABASE \"matrix-synapse\" WITH OWNER \"matrix-synapse\" \
             TEMPLATE template0 ENCODING 'UTF8' LC_COLLATE 'C' LC_CTYPE 'C'"
    '';
  };

  # cloudflared と、この先ブリッジが podman 側から届く必要がある。閉じていると DROP
  # なので接続拒否ではなくタイムアウトになり、ブリッジ側は「homeserver に繋がらない」
  # としか言わない。Conduit が 6167 を開けていたのと露出範囲は同じ。
  networking.firewall.allowedTCPPorts = [ 8008 ];
}
