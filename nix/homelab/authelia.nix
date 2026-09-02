# Authelia. homeserver の各サービスの前に置く SSO。
#
# ## なぜ Authentik ではないか
#
# Authentik は設定をデータベースに持ち、Web UI のフローエディタで編集する。宣言できない。
# それは uptime-kuma を捨てた理由と同じ形で (監視リストが誰もレビューできない SQLite に
# 入っていた)、ここでもう一度作りたくない。Authelia は設定が YAML 1 枚、ユーザーもファイル、
# 秘密は /var/lib/secrets の下、で完結する。差分が git に出るし、まっさらな箱でも同じ形に戻る。
#
# ## 何を守るか
#
# 掛ける先は hosts/homeserver.nix の `sites` にある `auth = true` のものだけ。あの表に
# ブラウザで見る UI と機械が叩くエンドポイントが混ざっているので、一律に掛けると
# iPhone の位置ログ (track)、Obsidian の同期 (obsidian)、ビルドキャッシュ (cache)、
# 通知 (ntfy) が黙って止まる。判断は表の側に書いてある。
#
# Vaultwarden (vault) はあえて外してある。パスワード保管庫を SSO の後ろに置くと、
# SSO のパスワードを思い出せないときに保管庫が開けない、という循環になる。
#
# ## 二要素
#
# `two_factor` を既定にしている。tailnet の中にいることを本人性の根拠にしない、という
# 判断。tailnet に載る端末が増えるほどその前提は弱くなるので。緩めるなら下の
# access_control の policy を one_factor にする (1 箇所)。
#
# 初回登録は notifier が file なので、リンクはメールではなくサーバー上のファイルに出る:
#   ssh homeserver sudo cat /var/lib/authelia-main/notification.txt
{
  config,
  lib,
  ...
}:
let
  port = 9092;
  domain = "gapul.net";
in
{
  services.authelia.instances.main = {
    enable = true;

    # 秘密は他の homelab と同じ扱い。sops-nix はまだこの箱に鍵を持っていないので
    # (homelab/README.md 参照)、install 時に手で置く root:0400 のファイル。
    secrets = {
      jwtSecretFile = "/var/lib/secrets/authelia/jwt";
      sessionSecretFile = "/var/lib/secrets/authelia/session";
      storageEncryptionKeyFile = "/var/lib/secrets/authelia/storage-encryption";
    };

    settings = {
      theme = "auto";
      server.address = "tcp://127.0.0.1:${toString port}";

      log = {
        level = "info";
        format = "text"; # journald が拾うので JSON にしない
      };

      # ユーザーは 1 人。LDAP を立てる理由が無い。
      # ファイルの中身は README の表に書いた形式で、パスワードは argon2id のハッシュ。
      authentication_backend = {
        password_reset.disable = true; # 通知経路がファイルしかないので窓口を開けない
        file = {
          path = "/var/lib/secrets/authelia/users.yml";
          watch = false;
        };
      };

      # 既定は deny。通す先は Caddy 側の forward_auth が付いた vhost だけなので、
      # ここは「gapul.net のサブドメイン全部を two_factor で通す」1 本で足りる。
      # サービスごとに強さを変えたくなったら、この上に個別の rule を積む。
      access_control = {
        default_policy = "deny";
        rules = [
          {
            domain = "*.${domain}";
            policy = "two_factor";
          }
        ];
      };

      session = {
        name = "authelia_session";
        # 親ドメインに載せることで、サブドメインを跨いでも 1 回のログインで済む。
        # これが SSO の実体。
        cookies = [
          {
            inherit domain;
            authelia_url = "https://auth.${domain}";
            default_redirection_url = "https://dash.${domain}";
            expiration = "12h";
            inactivity = "2h";
            remember_me = "1M";
          }
        ];
      };

      regulation = {
        max_retries = 4;
        find_time = "2m";
        ban_time = "10m";
      };

      storage.local.path = "/var/lib/authelia-main/db.sqlite3";

      # SMTP を持たない。TOTP の登録リンクはファイルに落ちる。
      notifier = {
        disable_startup_check = true;
        filesystem.filename = "/var/lib/authelia-main/notification.txt";
      };

      totp = {
        issuer = domain;
        algorithm = "sha1"; # 認証アプリの互換性が一番広い
        period = 30;
      };
    };
  };
}
