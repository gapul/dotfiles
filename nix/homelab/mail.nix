# Mail. Stalwart (IMAP/JMAP, submission endpoint, admin UI) plus imapsync mirroring 3 Google accounts.
#
# The home line has OP25B, so port 25 passes neither in nor out (measured 2026-09-23). So inbound (MX)
# stays on Google for now, and Gmail, work, and university (all Google IMAP) are mirrored hourly
# with imapsync. Deletions on the Google side are not mirrored (this side is the archive).
#
# Outbound is split by From identity so that replies go out "under the identity it was received as".
# Mail under a Google identity is accepted on Stalwart's 465 and sent via that account's Google SMTP,
# authenticating with the same app password. Google keeps a copy in its own Sent, which comes back
# to Stalwart on the next mirror, so both inbox and Sent stay in sync with Google. There is no exit
# for the gapul.net identity yet (add one route once a relay such as Sakura is chosen).
#
# Accounts are declared in Stalwart's memory directory. 1 account = 1 Google account.
# The three files /var/lib/secrets/mail/<name>.{password,address,app-password} are read by both
# Stalwart (via the %{file:}% macro through LoadCredential) and imapsync.
# address and app-password are the credentials for both the mirror source (imapsync) and the exit (relay).
# An account with an empty app-password skips the mirror, and Google rejects sending under that identity.
# In other words, the other accounts work even if not all app passwords are in place.
#
# TLS uses Stalwart's own ACME (dns-01, with the same Cloudflare token as lego passed via
# EnvironmentFile). Borrowing Caddy's wildcard certificate would require wiring a restart on every
# renewal, which is more fragile. Only HTTP (JMAP and admin UI) goes through Caddy
# (mail.gapul.net → 8120); IMAPS 993 and submissions 465 are direct on the tailnet
# (trustedInterfaces = tailscale0, so no firewall opening). imapsync also enters the same 993 over
# loopback. Plaintext 143 is not offered because Stalwart refuses LOGIN ("LOGIN is disabled on
# the clear-text port").
{ pkgs, ... }:
let
  # Stalwart account name → that Google account's domain (to pick the outbound route by From).
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

  # Maps each account's three files from LoadCredential names (<name>.<kind>) to the real files.
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
        # Submission endpoint for clients (Roundcube, Mail.app, aerc). Authentication required.
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
        # Required field (without it ACME stops entirely with "Missing property" and stays self-signed).
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
          # Use the real address as the identity. must-match-sender (default true) checks this, so once
          # authenticated as this account, From can only be this address.
          email = [ (cred "${name}.address") ];
        }) accounts;
      };
      authentication.fallback-admin = {
        user = "admin";
        secret = cred "admin.password";
      };

      # 465 is usable only after auth, and only authenticated accounts may relay out (the default, but explicit).
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

      # Pick the exit by From domain. No match falls to mx (unreachable under OP25B = an identity that can't send).
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
