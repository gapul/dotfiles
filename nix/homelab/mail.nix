# Mail. Stalwart (IMAP/JMAP, submission endpoint, admin UI) plus imapsync mirroring 3 Google accounts.
#
# The home line has OP25B, so port 25 passes neither in nor out (measured 2026-09-23). So inbound (MX)
# stays on Google for now, and Gmail, work, and university (all Google IMAP) are mirrored hourly
# with imapsync. Deletions on the Google side are not mirrored (this side is the archive).
# On top of the hourly pass, mail-push-<name> holds an IMAP IDLE on each Google INBOX and copies
# just the INBOX the moment something arrives, so new mail reaches the clients (which IDLE on
# Stalwart in turn) in seconds rather than up to an hour later.
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

  # Both the hourly pass and the push watchers run as this user, so they can share the lock dir.
  mirrorUser = "mail-mirror";
  lockDir = "/run/mail-mirror-lock";

  # One imapsync run over one part of one account; extra arguments go to imapsync and pick the
  # folders. The hourly pass and a push can fire together, and two imapsync runs that both see a
  # message missing from the same Stalwart folder would both append it, so runs over the same part
  # are serialised by flock. The lock is per part, not per account: the hourly pass over the other
  # folders takes about 10 minutes ([Gmail]/All Mail), and a push that waited on it would arrive
  # that late (17:41 → 17:51 on 2026-10-16). INBOX alone takes about a minute.
  syncAccount = pkgs.writeShellScript "mail-sync-account" ''
    set -u
    name=$1
    part=$2
    shift 2
    if [ ! -s "$CREDENTIALS_DIRECTORY/$name.app-password" ]; then
      echo "$name: Google のアプリパスワードが未設定 (secrets の mail/$name.app-password)、飛ばす"
      exit 0
    fi
    # imapsync は /run/credentials 配下のファイルを「読めない」と拒む (2026-09-23 実測、
    # exit 66) ので、両方のパスワードを自分の RuntimeDirectory に写してから渡す。
    work=$(mktemp -d "$RUNTIME_DIRECTORY/$name.XXXXXX")
    trap 'rm -rf "$work"' EXIT
    cat "$CREDENTIALS_DIRECTORY/$name.app-password" > "$work/src.password"
    cat "$CREDENTIALS_DIRECTORY/$name.password" > "$work/dst.password"
    exec 9> "${lockDir}/$name.$part.lock"
    ${pkgs.util-linux}/bin/flock 9
    # --gmail1: imap.gmail.com:993、[Gmail] の親フォルダを除き、ラベルはフォルダのまま、
    # "All Mail" は最後に回して他フォルダに写した分を重複させない。
    ${pkgs.imapsync}/bin/imapsync --gmail1 --user1 "$(cat "$CREDENTIALS_DIRECTORY/$name.address")" \
      --passfile1 "$work/src.password" \
      --host2 127.0.0.1 --port2 993 --ssl2 \
      --user2 "$name" --passfile2 "$work/dst.password" \
      --automap --nofoldersizes --noreleasecheck --nolog --tmpdir "$work" \
      --pidfile "$work/pid" "$@" || { status=$?; echo "$name: imapsync が $status で終了"; exit 1; }
  '';

  mirror = pkgs.writeShellScript "mail-mirror" ''
    set -u
    status=0
    for name in ${toString names}; do
      ${syncAccount} "$name" inbox --folder INBOX || status=1
      ${syncAccount} "$name" rest --exclude '^INBOX$' || status=1
    done
    exit $status
  '';

  # The push watcher for one account. goimapnotify discards its hooks' output, so the hook sends
  # its own to the journal under the unit's name. --maxage keeps the INBOX pass to the last couple
  # of days: it only has to catch what just arrived, and the hourly pass covers everything else.
  pushConfig =
    name:
    (pkgs.formats.json { }).generate "goimapnotify-${name}.json" {
      configurations = [
        {
          host = "imap.gmail.com";
          port = 993;
          tls = true;
          # goimapnotify skips certificate verification unless told otherwise, and this
          # connection carries the Google app password.
          tlsOptions.rejectUnauthorized = true;
          usernameCMD = "cat \"$CREDENTIALS_DIRECTORY/${name}.address\"";
          passwordCMD = "cat \"$CREDENTIALS_DIRECTORY/${name}.app-password\"";
          boxes = [
            {
              mailbox = "INBOX";
              onNewMail = "systemd-cat -t mail-push-${name} ${syncAccount} ${name} inbox --folder INBOX --maxage 2";
            }
          ];
        }
      ];
    };
  push = pkgs.writeShellScript "mail-push" ''
    set -u
    name=$1
    # No app password means no mirror either (see syncAccount). Exit cleanly so the unit stays
    # inactive instead of restart-looping until one is put in.
    if [ ! -s "$CREDENTIALS_DIRECTORY/$name.app-password" ]; then
      echo "$name: Google のアプリパスワードが未設定、IDLE 監視はしない"
      exit 0
    fi
    exec ${pkgs.goimapnotify}/bin/goimapnotify -conf "$2"
  '';

  mirrorServiceConfig = {
    User = mirrorUser;
    Group = mirrorUser;
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    NoNewPrivileges = true;
    ReadWritePaths = [ lockDir ];
  };

  # One IDLE watcher per account (see push).
  pushUnits = builtins.listToAttrs (
    map (name: {
      name = "mail-push-${name}";
      value = {
        description = "${name} の Google INBOX を IMAP IDLE で見張り、届いたらすぐ Stalwart に写す";
        after = [
          "stalwart.service"
          "network-online.target"
        ];
        wants = [ "network-online.target" ];
        requires = [ "stalwart.service" ];
        wantedBy = [ "multi-user.target" ];
        environment.HOME = "/run/mail-push-${name}";
        # goimapnotify runs every hook through `sh -c`.
        path = [ pkgs.bash ];
        serviceConfig = mirrorServiceConfig // {
          RuntimeDirectory = "mail-push-${name}";
          WorkingDirectory = "/run/mail-push-${name}";
          LoadCredential = map (kind: "${name}.${kind}:${secretDir}/${name}.${kind}") [
            "password"
            "address"
            "app-password"
          ];
          ExecStart = "${push} ${name} ${pushConfig name}";
          # Gmail drops long IDLE sessions and the line drops now and then; goimapnotify
          # reconnects by itself, and this covers it giving up.
          Restart = "on-failure";
          RestartSec = 30;
        };
        unitConfig = {
          StartLimitIntervalSec = 600;
          StartLimitBurst = 5;
        };
        onFailure = [ "ntfy-failure@%n.service" ];
      };
    }) names
  );

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
  systemd.services = pushUnits // {
    stalwart.serviceConfig.EnvironmentFile = "/var/lib/secrets/acme-cloudflare.env";

    mail-mirror = {
      description = "Google の各口座を Stalwart に写す (毎時)";
      after = [ "stalwart.service" ];
      requires = [ "stalwart.service" ];
      environment.HOME = "/run/mail-mirror";
      serviceConfig = mirrorServiceConfig // {
        Type = "oneshot";
        RuntimeDirectory = "mail-mirror";
        WorkingDirectory = "/run/mail-mirror";
        LoadCredential = builtins.attrValues (builtins.mapAttrs (k: v: "${k}:${v}") accountCredentials);
        ExecStart = mirror;
      };
      onFailure = [ "ntfy-failure@%n.service" ];
    };
  };
  systemd.timers.mail-mirror = {
    description = "メールの写しを毎時";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* *:41:00";
      Persistent = true;
    };
  };

  users.users.${mirrorUser} = {
    isSystemUser = true;
    group = mirrorUser;
  };
  users.groups.${mirrorUser} = { };

  systemd.tmpfiles.rules = [
    "d ${secretDir} 0700 root root -"
    "d ${lockDir} 0700 ${mirrorUser} ${mirrorUser} -"
  ];
}
