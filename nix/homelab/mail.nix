# メール。Stalwart (IMAP/JMAP、送信の受け口、管理画面) と、Google の3アカウントを写す imapsync。
#
# 家の回線は OP25B で 25 番が出入りとも通らない (2026-09-23 実測)。なので受信 (MX) は
# まだ Google のまま、Gmail・会社・大学 (どれも Google の IMAP) を毎時 imapsync で写す。
# Google 側の削除は写さない (こちらは保管庫)。
#
# 送信は「受け取った名義で返す」ために、From の名義ごとに出口を分ける。Google 名義の
# メールは Stalwart の 465 で受けて、その口座の Google SMTP に同じアプリパスワードで
# 認証して出す。Google が自分の送信済みに控えを残すので、次の写しで Stalwart 側にも
# 戻ってきて、受信も送信済みも Google 側と揃ったままになる。gapul.net 名義の出口は
# まだ無い (さくら等のリレーを決めたら route を1つ足す)。
#
# 口座は Stalwart の memory ディレクトリで宣言する。1 口座 = 1 Google アカウント。
# /var/lib/secrets/mail/<name>.{password,address,app-password} の3ファイルを、
# Stalwart (LoadCredential 経由の %{file:}% マクロ) と imapsync の両方が読む。
# address と app-password が写し元 (imapsync) と出口 (relay) の両方の資格情報。
# app-password が空の口座は写しを飛ばし、その名義の送信は Google に蹴られる。
# つまりアプリパスワードが揃っていなくても他の口座は動く。
#
# TLS は Stalwart 自身の ACME (dns-01、lego と同じ Cloudflare トークンを
# EnvironmentFile で渡す)。Caddy のワイルドカード証明書を借りると更新のたびに
# 再起動を仕込む必要があり、そちらの方が壊れやすい。HTTP (JMAP と管理画面) だけは
# Caddy 経由 (mail.gapul.net → 8120)、IMAPS 993 と submissions 465 は tailnet に直接
# (trustedInterfaces = tailscale0 なので firewall は開けない)。imapsync も同じ 993 に
# ループバックで入る。平文の 143 は Stalwart が LOGIN を拒む ("LOGIN is disabled on
# the clear-text port") ので置かない。
{ pkgs, ... }:
let
  # Stalwart の口座名 → その Google アカウントのドメイン (送信の経路を From で選ぶため)。
  accounts = {
    gmail = "gmail.com";
    work = "mvrks.co.jp";
    school = "g.ecc.u-tokyo.ac.jp";
  };
  names = builtins.attrNames accounts;
  secretDir = "/var/lib/secrets/mail";
  cred = name: "%{file:/run/credentials/stalwart.service/${name}}%";

  mirror = pkgs.writeShellScript "mail-mirror" ''
    set -u
    status=0
    for name in ${toString names}; do
      if [ ! -s "$CREDENTIALS_DIRECTORY/$name.app-password" ]; then
        echo "$name: Google のアプリパスワードが未設定 (secrets の mail/$name.app-password)、飛ばす"
        continue
      fi
      # imapsync は /run/credentials 配下のファイルを「読めない」と拒む (2026-09-23 実測、
      # exit 66) ので、両方のパスワードを自分の RuntimeDirectory に写してから渡す。
      cat "$CREDENTIALS_DIRECTORY/$name.app-password" > "$RUNTIME_DIRECTORY/src.password"
      cat "$CREDENTIALS_DIRECTORY/$name.password" > "$RUNTIME_DIRECTORY/dst.password"
      # --gmail1: imap.gmail.com:993、[Gmail] の親フォルダを除き、ラベルはフォルダのまま、
      # "All Mail" は最後に回して他フォルダに写した分を重複させない。
      ${pkgs.imapsync}/bin/imapsync --gmail1 --user1 "$(cat "$CREDENTIALS_DIRECTORY/$name.address")" \
        --passfile1 "$RUNTIME_DIRECTORY/src.password" \
        --host2 127.0.0.1 --port2 993 --ssl2 \
        --user2 "$name" --passfile2 "$RUNTIME_DIRECTORY/dst.password" \
        --automap --nofoldersizes --noreleasecheck --nolog --tmpdir "$RUNTIME_DIRECTORY" \
        --pidfile "$RUNTIME_DIRECTORY/$name.pid" || { echo "$name: imapsync が $? で終了"; status=1; }
      rm -f "$RUNTIME_DIRECTORY/src.password" "$RUNTIME_DIRECTORY/dst.password"
    done
    exit $status
  '';

  # 口座ごとの3ファイルを LoadCredential の名前 (<name>.<kind>) → 実体に。
  accountCredentials = builtins.listToAttrs (
    builtins.concatMap (
      name:
      map
        (kind: {
          name = "${name}.${kind}";
          value = "${secretDir}/${name}.${kind}";
        })
        [
          "password"
          "address"
          "app-password"
        ]
    ) names
  );
in
{
  services.stalwart = {
    enable = true;
    stateVersion = "26.05";
    credentials = {
      "admin.password" = "${secretDir}/admin.password";
    }
    // accountCredentials;
    settings = {
      server.hostname = "mail.gapul.net";
      server.http = {
        url = "https://mail.gapul.net";
        use-x-forwarded = true;
      };
      server.listener = {
        imaps = {
          bind = [ "[::]:993" ];
          protocol = "imap";
          tls.implicit = true;
        };
        # クライアント (Roundcube、Mail.app、aerc) からの送信の受け口。認証必須。
        submissions = {
          bind = [ "[::]:465" ];
          protocol = "smtp";
          tls.implicit = true;
        };
        http = {
          bind = [ "127.0.0.1:8120" ];
          protocol = "http";
        };
      };
      acme.cloudflare = {
        directory = "https://acme-v02.api.letsencrypt.org/directory";
        challenge = "dns-01";
        provider = "cloudflare";
        secret = "%{env:CF_DNS_API_TOKEN}%";
        domains = [ "mail.gapul.net" ];
        # 必須項目 (無いと "Missing property" で ACME 全体が止まり、自己署名のまま)。
        contact = [ "gapul@gapul.net" ];
        renew-before = "30d";
        default = true;
      };
      storage.directory = "memory";
      directory.memory = {
        type = "memory";
        principals = builtins.mapAttrs (name: _: {
          inherit name;
          class = "individual";
          secret = cred "${name}.password";
          # 実アドレスを名義にする。must-match-sender (既定 true) がここを見るので、
          # この口座で認証したら From はこのアドレスしか出せない。
          email = [ (cred "${name}.address") ];
        }) accounts;
      };
      authentication.fallback-admin = {
        user = "admin";
        secret = cred "admin.password";
      };

      # 465 は認証してからしか使えず、認証した口座だけ外へ中継できる (既定と同じだが明示)。
      session.auth.require = [
        {
          "if" = "listener = 'submissions'";
          "then" = true;
        }
        { "else" = false; }
      ];
      session.rcpt.relay = [
        {
          "if" = "!is_empty(authenticated_as)";
          "then" = true;
        }
        { "else" = false; }
      ];

      # 出口は From のドメインで選ぶ。該当が無ければ mx (OP25B で届かない = 出せない名義)。
      queue.strategy.route =
        builtins.attrValues (
          builtins.mapAttrs (name: domain: {
            "if" = "sender_domain = '${domain}'";
            "then" = "'${name}'";
          }) accounts
        )
        ++ [ { "else" = "'mx'"; } ];
      queue.route = builtins.mapAttrs (name: _: {
        type = "relay";
        address = "smtp.gmail.com";
        port = 465;
        protocol = "smtp";
        tls.implicit = true;
        auth.username = cred "${name}.address";
        auth.secret = cred "${name}.app-password";
      }) accounts;
    };
  };
  systemd.services.stalwart.serviceConfig.EnvironmentFile = "/var/lib/secrets/acme-cloudflare.env";

  systemd.services.mail-mirror = {
    description = "Google の各口座を Stalwart に写す (毎時)";
    after = [ "stalwart.service" ];
    requires = [ "stalwart.service" ];
    environment.HOME = "/run/mail-mirror";
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      RuntimeDirectory = "mail-mirror";
      WorkingDirectory = "/run/mail-mirror";
      LoadCredential = builtins.attrValues (builtins.mapAttrs (k: v: "${k}:${v}") accountCredentials);
      ExecStart = mirror;
    };
    onFailure = [ "ntfy-failure@%n.service" ];
  };
  systemd.timers.mail-mirror = {
    description = "メールの写しを毎時";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* *:41:00";
      Persistent = true;
    };
  };

  systemd.tmpfiles.rules = [ "d ${secretDir} 0700 root root -" ];
}
