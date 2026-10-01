# Household ledger. The Beancount ledger (/var/lib/ledger/book), the scheduled jobs that fill
# it, and Fava to read it.
#
# Moved from macmini on 2026-09-23. The ledger is a must-not-stop job ("pull Zaim hourly,
# reconcile balances daily"), and macmini is not an always-on machine. Here it is
# self-contained next to Caddy (money.gapul.net → 127.0.0.1:5075), and restic picks it up
# with the rest of /var/lib.
#
# The code is zaim/ and crypto/ from personal-tools (private repo). The policy is not to keep
# repository clones on this box, so it pulls every time with a read-only deploy key
# (/var/lib/secrets/ledger-deploy.key; "homeserver-ledger" on the GitHub side).
#
# Secrets are the Zaim cookie (/var/lib/secrets/zaim.cookie; run `zaim_web.py login` on the
# main Mac and scp it. It expires 2 hours after the last access, so the hourly sync also keeps
# it alive), the key above, and the Wise personal API token (sops. Personal accounts can no
# longer register an SCA public key, so balance statements are unreadable; this is built only
# on the SCA-free activity API and balances). All are passed via LoadCredential and kept where
# the ledger user cannot read them.
#
# Revolut is the exception to "everything runs here": its web app is behind Cloudflare's bot
# check, so a headed browser on macmini fetches it and pushes the JSON into incoming/.
#
# Failure notifications go through ntfy-failure@ like other jobs. But an expired cookie keeps
# failing every hour until fixed, so consecutive failures for the same reason exit 0 from the
# second one on, keeping it to one notification (same as in the macmini days).
{
  pkgs,
  ...
}:
let
  home = "/var/lib/ledger";
  book = "${home}/book";
  tools = "${home}/personal-tools";
  incoming = "${home}/incoming"; # files pushed from other machines (Revolut dump from macmini)
  py = "${pkgs.python3}/bin/python3";
  beanCheck = "${pkgs.beancount}/bin/bean-check";

  githubKnownHosts = pkgs.writeText "github-known-hosts" ''
    github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
  '';
  gitSsh = pkgs.writeShellScript "ledger-git-ssh" ''
    exec ${pkgs.openssh}/bin/ssh -i "$CREDENTIALS_DIRECTORY/deploy-key" \
      -o IdentitiesOnly=yes -o UserKnownHostsFile=${githubKnownHosts} "$@"
  '';

  # Shared part of each job: update personal-tools, and notify each failure reason only once.
  prelude = name: ''
    set -u
    export GIT_SSH_COMMAND=${gitSsh}
    git() { ${pkgs.git}/bin/git -c user.name=ledger -c user.email=ledger@homeserver "$@"; }
    state="${home}/.${name}.failed"
    fail() {
      echo "$1" >&2
      if [ "$(cat "$state" 2>/dev/null)" = "$1" ]; then exit 0; fi
      printf '%s' "$1" > "$state"
      exit 1
    }
    if [ -d ${tools}/.git ]; then
      out=$(git -C ${tools} pull -q --ff-only 2>&1) || fail "personal-tools の pull に失敗: $out"
    else
      out=$(git clone -q git@github.com:gapul/personal-tools.git ${tools} 2>&1) || fail "personal-tools の clone に失敗: $out"
    fi
    commit() {
      if [ -n "$(git -C ${book} status --porcelain)" ]; then
        git -C ${book} add -A && git -C ${book} commit -q -m "$1 $(date +%F\ %H:%M)"
      fi
    }
  '';

  zaimSync = pkgs.writeShellScript "zaim-sync" ''
    ${prelude "zaim-sync"}
    out=$(${py} ${tools}/zaim/zaim_web.py sync --db ${book}/zaim.db 2>&1) ||
      fail "Zaim の同期に失敗: $out (Cookie 切れなら母艦で zaim_web.py login → scp ~/.cache/zaim/cookie homeserver:/var/lib/secrets/zaim.cookie)"
    out=$(${py} ${tools}/zaim/zaim_beancount.py --db ${book}/zaim.db --rules ${book}/rules.toml \
      --out ${book}/zaim.beancount 2>&1) || fail "帳簿の生成に失敗: $out"
    out=$(${beanCheck} ${book}/main.beancount 2>&1) || fail "bean-check: $out"
    rm -f "$state"
    commit "zaim sync"
  '';

  cryptoSync = pkgs.writeShellScript "crypto-sync" ''
    ${prelude "crypto-sync"}
    [ -f ${book}/wallets.toml ] || exit 0
    out=$(${py} ${tools}/crypto/crypto_beancount.py --wallets ${book}/wallets.toml \
      --balances ${book}/crypto-balances.beancount --prices ${book}/crypto-prices.beancount 2>&1) ||
      fail "残高の取得に失敗: $out"
    out=$(${beanCheck} ${book}/main.beancount 2>&1) ||
      fail "bean-check: $out (送金やガスを crypto.beancount に書き漏れていないか)"
    rm -f "$state"
    commit "crypto sync"
  '';

  wiseSync = pkgs.writeShellScript "wise-sync" ''
    ${prelude "wise-sync"}
    out=$(${py} ${tools}/wise/wise_beancount.py --token-file "$CREDENTIALS_DIRECTORY/wise-token" \
      --rules ${book}/rules.toml --out ${book}/wise.beancount 2>&1) ||
      fail "Wise の取り込みに失敗: $out"
    out=$(${beanCheck} ${book}/main.beancount 2>&1) || fail "bean-check: $out"
    rm -f "$state"
    commit "wise sync"
  '';

  # Revolut has no personal API and app.revolut.com sits behind Cloudflare's bot check, so the
  # fetch happens on macmini (home/macmini-revolut.nix: a headed Helium with a logged-in
  # profile, driven over CDP), which scp's the JSON here. This side only renders it; the path
  # unit below runs it whenever the file lands.
  revolutSync = pkgs.writeShellScript "revolut-sync" ''
    ${prelude "revolut-sync"}
    [ -s ${incoming}/revolut.json ] || exit 0
    out=$(${py} ${tools}/revolut/revolut_beancount.py --dump ${incoming}/revolut.json \
      --rules ${book}/rules.toml --out ${book}/revolut.beancount 2>&1) ||
      fail "Revolut の帳簿生成に失敗: $out"
    out=$(${beanCheck} ${book}/main.beancount 2>&1) || fail "bean-check: $out"
    rm -f "$state"
    commit "revolut sync"
  '';

  # Send one line to ntfy (same topic and token as ntfy-failure@). Not for failures, but for
  # notices that need a human to act.
  notify = pkgs.writeShellScript "ledger-notify" ''
    set -u
    ${pkgs.curl}/bin/curl -fsS --max-time 15 -H "Authorization: Bearer $NTFY_TOKEN" \
      -H "Title: $1" -H "Tags: ledger" -d "$2" "http://127.0.0.1:8082/$NTFY_TOPIC" >/dev/null
  '';

  # When a Zaim account link stops fetching, Zaim says nothing (in 2026-09 we missed that
  # SBI Sumishin Net Bank, PayPay Bank and Rakuten Bank had stopped over the summer). Notify
  # when an account's latest date is old.
  zaimStale = pkgs.writeShellScript "zaim-stale-check" ''
    set -u
    stale=$(${py} - ${book}/zaim.db <<'PY'
    import sqlite3, sys, datetime
    db = sqlite3.connect(sys.argv[1])
    limit = (datetime.date.today() - datetime.timedelta(days=21)).isoformat()
    rows = db.execute("""
      SELECT acct, MAX(date) FROM (
        SELECT from_account AS acct, date FROM transactions WHERE deleted_at IS NULL AND from_account IS NOT NULL
        UNION ALL
        SELECT to_account, date FROM transactions WHERE deleted_at IS NULL AND to_account IS NOT NULL)
      GROUP BY acct HAVING MAX(date) < ?
      ORDER BY 2""", (limit,)).fetchall()
    for acct, last in rows:
        print(f"{acct}: 最終 {last}")
    PY
    )
    [ -z "$stale" ] || ${notify} "Zaim の連携が止まっている口座" "$stale"
    # The Revolut dump comes from macmini. Its own failures notify from there, but if macmini
    # is down or the agent is gone, nothing arrives and nothing says so.
    if [ -z "$(find ${incoming} -maxdepth 1 -name revolut.json -mtime -3 2>/dev/null)" ]; then
      ${notify} "Revolut の取り込みが 3 日以上届いていない" "macmini の revolut-dump (launchd) か、Revolut のセッション (母艦で revolut_web.py login → プロファイルを rsync) を見る"
    fi
  '';

  common = {
    User = "ledger";
    Group = "ledger";
    WorkingDirectory = home;
    LoadCredential = [ "deploy-key:/var/lib/secrets/ledger-deploy.key" ];
  };
in
{
  users.users.ledger = {
    isSystemUser = true;
    group = "ledger";
    inherit home;
  };
  users.groups.ledger = { };
  # Z: the tree tarred over from macmini is still uid 501, so fix the ownership here.
  systemd.tmpfiles.rules = [
    "d ${home} 0750 ledger ledger -"
    "Z ${home} - ledger ledger -"
    # macmini scp's as root; ownership of what lands there is fixed by the service itself.
    "d ${incoming} 0750 ledger ledger -"
  ];

  systemd.services.zaim-sync = {
    description = "Zaim → SQLite → Beancount (毎時)";
    environment.ZAIM_COOKIE_CACHE = "%d/zaim-cookie";
    serviceConfig = common // {
      Type = "oneshot";
      LoadCredential = common.LoadCredential ++ [ "zaim-cookie:/var/lib/secrets/zaim.cookie" ];
      ExecStart = zaimSync;
    };
    onFailure = [ "ntfy-failure@%n.service" ];
  };
  systemd.timers.zaim-sync = {
    description = "Zaim の同期を毎時 (Cookie の延命も兼ねる)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* *:17:00";
      Persistent = true;
    };
  };

  systemd.services.crypto-sync = {
    description = "暗号資産の残高と円価格 → Beancount (毎日)";
    serviceConfig = common // {
      Type = "oneshot";
      ExecStart = cryptoSync;
    };
    onFailure = [ "ntfy-failure@%n.service" ];
  };
  systemd.timers.crypto-sync = {
    description = "暗号資産の残高の突き合わせを毎日";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Daily is enough: the free RPC and CoinGecko are rate-limited, and balances only move
      # when hand-written transactions are added.
      OnCalendar = "*-*-* 06:40:00";
      Persistent = true;
    };
  };

  systemd.services.wise-sync = {
    description = "Wise の残高明細 → Beancount (毎日)";
    serviceConfig = common // {
      Type = "oneshot";
      LoadCredential = common.LoadCredential ++ [ "wise-token:/var/lib/secrets/wise.token" ];
      ExecStart = wiseSync;
    };
    onFailure = [ "ntfy-failure@%n.service" ];
  };
  systemd.timers.wise-sync = {
    description = "Wise の明細取り込みを毎日";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Re-fetch all activity every time, rebuild wise.beancount entirely, absorb the difference
      # from the real balance as fees, then place the balance. A low-activity account, so daily
      # is enough.
      OnCalendar = "*-*-* 06:50:00";
      Persistent = true;
    };
  };

  systemd.services.revolut-sync = {
    description = "Revolut の dump (macmini から) → Beancount";
    serviceConfig = common // {
      Type = "oneshot";
      ExecStart = revolutSync;
    };
    onFailure = [ "ntfy-failure@%n.service" ];
  };
  systemd.paths.revolut-sync = {
    description = "Revolut の dump が届いたら帳簿にする";
    wantedBy = [ "multi-user.target" ];
    # The sender writes to a temp name and mv's into place, so one trigger per delivery.
    pathConfig.PathChanged = "${incoming}/revolut.json";
  };

  systemd.services.zaim-stale-check = {
    description = "Zaim の口座連携が止まっていないか (毎日)";
    serviceConfig = common // {
      Type = "oneshot";
      EnvironmentFile = "/var/lib/secrets/gatus.env";
      ExecStart = zaimStale;
    };
    onFailure = [ "ntfy-failure@%n.service" ];
  };
  systemd.timers.zaim-stale-check = {
    description = "Zaim の連携停止の検知を毎日";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 07:10:00";
      Persistent = true;
    };
  };

  # (The yearly Minna Bank PDF reminder was here. The account is no longer used as of
  # 2026-10; what it had is in minna.beancount already.)

  # Fava picks up ledger file changes by itself, so no restart is needed after a sync.
  systemd.services.fava = {
    description = "Fava (Beancount の閲覧)";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = common // {
      ExecStart = "${pkgs.fava}/bin/fava --host 127.0.0.1 --port 5075 ${book}/main.beancount";
      Restart = "on-failure";
    };
  };
}
