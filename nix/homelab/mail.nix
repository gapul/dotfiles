# メール。Stalwart (IMAP/JMAP、管理画面) と、Google の3アカウントを写す imapsync。
#
# 家の回線は OP25B で 25 番が出入りとも通らない (2026-09-23 実測)。なので今はまだ
# 送受信を持たず、保存と閲覧だけをここに置く。Gmail・会社・大学はどれも Google の
# IMAP なので、毎時 imapsync で写す。Google 側の削除は写さない (こちらは保管庫)。
# 送受信を移すときは入口 (MX) と出口 (リレー) を足すだけで、置き場はこのまま。
#
# 口座は Stalwart の memory ディレクトリで宣言する。1 口座 = 1 写し元。パスワードは
# /var/lib/secrets/mail/<name>.password で、Stalwart (LoadCredential 経由の
# %{file:}% マクロ) と imapsync の両方が同じファイルを読む。
#
# TLS は Stalwart 自身の ACME (dns-01、lego と同じ Cloudflare トークンを
# EnvironmentFile で渡す)。Caddy のワイルドカード証明書を借りると更新のたびに
# 再起動を仕込む必要があり、そちらの方が壊れやすい。HTTP (JMAP と管理画面) だけは
# Caddy 経由 (mail.gapul.net → 8120)、IMAPS 993 は tailnet に直接
# (trustedInterfaces = tailscale0 なので firewall は開けない)。imapsync も同じ 993 に
# ループバックで入る。平文の 143 は Stalwart が LOGIN を拒む ("LOGIN is disabled on
# the clear-text port") ので置かない。
#
# 写し元の資格情報 (mail/mirror-<name>.env の SRC_USER と SRC_PASSWORD) が空の口座は
# 飛ばすだけなので、アプリパスワードが揃っていなくても他の口座は動く。
{ pkgs, ... }:
let
  accounts = [
    "gmail"
    "work"
    "school"
  ];
  secretDir = "/var/lib/secrets/mail";
  cred = name: "%{file:/run/credentials/stalwart.service/${name}-password}%";

  mirror = pkgs.writeShellScript "mail-mirror" ''
    set -u
    status=0
    for name in ${toString accounts}; do
      SRC_USER=""; SRC_PASSWORD=""
      . "$CREDENTIALS_DIRECTORY/$name.env"
      if [ -z "$SRC_PASSWORD" ]; then
        echo "$name: 写し元の資格情報が未設定 (secrets の mail/mirror-$name.env)、飛ばす"
        continue
      fi
      # imapsync は /run/credentials 配下のファイルを「読めない」と拒む (2026-09-23 実測、
      # exit 66) ので、両方のパスワードを自分の RuntimeDirectory に写してから渡す。
      printf '%s' "$SRC_PASSWORD" > "$RUNTIME_DIRECTORY/src.password"
      cat "$CREDENTIALS_DIRECTORY/$name.password" > "$RUNTIME_DIRECTORY/dst.password"
      # --gmail1: imap.gmail.com:993、[Gmail] の親フォルダを除き、ラベルはフォルダのまま、
      # "All Mail" は最後に回して他フォルダに写した分を重複させない。
      ${pkgs.imapsync}/bin/imapsync --gmail1 --user1 "$SRC_USER" --passfile1 "$RUNTIME_DIRECTORY/src.password" \
        --host2 127.0.0.1 --port2 993 --ssl2 \
        --user2 "$name" --passfile2 "$RUNTIME_DIRECTORY/dst.password" \
        --automap --nofoldersizes --noreleasecheck --nolog --tmpdir "$RUNTIME_DIRECTORY" \
        --pidfile "$RUNTIME_DIRECTORY/$name.pid" || { echo "$name: imapsync が $? で終了"; status=1; }
      rm -f "$RUNTIME_DIRECTORY/src.password" "$RUNTIME_DIRECTORY/dst.password"
    done
    exit $status
  '';
in
{
  services.stalwart = {
    enable = true;
    stateVersion = "26.05";
    credentials = {
      admin-password = "${secretDir}/admin.password";
    }
    // builtins.listToAttrs (
      map (name: {
        name = "${name}-password";
        value = "${secretDir}/${name}.password";
      }) accounts
    );
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
        principals = builtins.listToAttrs (
          map (name: {
            inherit name;
            value = {
              inherit name;
              class = "individual";
              secret = cred name;
              email = [ "${name}@mail.gapul.net" ];
            };
          }) accounts
        );
      };
      authentication.fallback-admin = {
        user = "admin";
        secret = cred "admin";
      };
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
      LoadCredential = builtins.concatMap (name: [
        "${name}.env:${secretDir}/mirror-${name}.env"
        "${name}.password:${secretDir}/${name}.password"
      ]) accounts;
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
