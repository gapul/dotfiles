# 家計簿。Beancount の台帳 (/var/lib/ledger/book) と、それを埋める定期ジョブ、読む Fava。
#
# 2026-09-23 に macmini から移した。台帳は「毎時 Zaim を引いて毎日残高を突き合わせる」
# 止まらない前提の仕事で、macmini は常駐機ではない。ここなら Caddy の隣で完結し
# (money.gapul.net → 127.0.0.1:5075)、restic も /var/lib ごと拾う。
#
# 中身は personal-tools (private repo) の zaim/ と crypto/。この箱にはリポジトリの
# クローンを置かない方針なので、read-only の deploy key (/var/lib/secrets/ledger-deploy.key、
# GitHub 側は "homeserver-ledger") で毎回 pull する。
#
# 秘密は2つ。Zaim の Cookie (/var/lib/secrets/zaim.cookie。母艦で `zaim_web.py login` して
# scp する。最後のアクセスから2時間で切れるので毎時の同期が延命でもある) と上の鍵。
# どちらも LoadCredential で渡し、ledger ユーザーからは読めない場所に置く。
#
# 失敗の通知は他のジョブと同じ ntfy-failure@。ただし Cookie 切れは直るまで毎時落ち続ける
# ので、同じ理由の連続失敗は2回目から exit 0 にして通知を1回に抑える (macmini 時代と同じ)。
{
  pkgs,
  ...
}:
let
  home = "/var/lib/ledger";
  book = "${home}/book";
  tools = "${home}/personal-tools";
  py = "${pkgs.python3}/bin/python3";
  beanCheck = "${pkgs.beancount}/bin/bean-check";

  githubKnownHosts = pkgs.writeText "github-known-hosts" ''
    github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
  '';
  gitSsh = pkgs.writeShellScript "ledger-git-ssh" ''
    exec ${pkgs.openssh}/bin/ssh -i "$CREDENTIALS_DIRECTORY/deploy-key" \
      -o IdentitiesOnly=yes -o UserKnownHostsFile=${githubKnownHosts} "$@"
  '';

  # 各ジョブの共通部: personal-tools を最新にし、失敗は理由ごとに1回だけ通知する。
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
  # Z: macmini から tar で持ってきた木は uid 501 のままなので、所有者をここで揃える。
  systemd.tmpfiles.rules = [
    "d ${home} 0750 ledger ledger -"
    "Z ${home} - ledger ledger -"
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
      # 日次で足りる: 無料 RPC と CoinGecko はレート制限があり、残高が動くのは
      # 手書きの取引を入れる時だけ。
      OnCalendar = "*-*-* 06:40:00";
      Persistent = true;
    };
  };

  # Fava は台帳ファイルの更新を自分で拾うので、同期後の再起動は要らない。
  systemd.services.fava = {
    description = "Fava (Beancount の閲覧)";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = common // {
      ExecStart = "${pkgs.fava}/bin/fava --host 127.0.0.1 --port 5075 ${book}/main.beancount";
      Restart = "on-failure";
    };
  };
}
