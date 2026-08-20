{ pkgs, ... }:
let
  # Same repository and the same retention as the Mac and the laptop. That file
  # is the single definition point on purpose: three hosts writing to one restic
  # repository with different forget policies is how snapshots get thinned out
  # from under each other.
  resticCommon = import ../lib/restic-common.nix { home = "/root"; };
in
{
  # Replaces backrest, the web UI for restic that ran as a container. The schedule
  # and the retention are the parts worth having in git; a UI to look at them is
  # not, and gatus already answers "did it run".
  services.restic.backups.homeserver = {
    inherit (resticCommon) repository;
    # Placed by hand at install time, like the other secrets here, until this host
    # has an age key for sops-nix.
    passwordFile = "/var/lib/secrets/restic.password";
    rcloneConfigFile = "/var/lib/secrets/rclone.conf";

    # /var/lib is where every service on this host keeps its state: the container
    # bind mounts under /var/lib/homelab, the named podman volumes, adguard,
    # syncthing's identity, gatus, the acme certs, samba's password db.
    paths = [
      "/var/lib"
      # Dawarich's postgres lives on the big disk, not in the named volume its compose file
      # suggests, so the whole /srv exclusion below was silently dropping the location history.
      # It is the Google Timeline replacement: nothing re-collects it.
      "/srv/dawarich"
    ];
    exclude = [
      # Container images are re-pullable and would dominate the repository. The
      # volumes directory underneath is deliberately not excluded — that is data.
      "/var/lib/containers/storage/overlay"
      "/var/lib/containers/storage/overlay-images"
      "/var/lib/containers/storage/overlay-layers"
      "/var/lib/containers/cache"
      # Runtime scratch, regenerated on boot.
      "/var/lib/systemd/coredump"
    ];
    # The rest of /srv is not backed up. It holds media, the attic cache and archivebox's
    # dumps: large, and either re-obtainable or already content-addressed. /srv/syncthing is
    # a copy of what the Mac holds and is backed up from there. /srv/dawarich is the one
    # exception and is listed above. Check this list again whenever a service is pointed at
    # the big disk — that is how the location history went missing.

    # --host: the repository is shared, and forget without it applies this policy to
    # every host's snapshots, not just the ones written here. The policy is the same
    # on every host so nothing gets thinned differently — but it does mean whoever
    # runs first expires the snapshots of hosts that no longer write any (pve's
    # vzdumps, the cold pass taken during the migration). Those are kept by the
    # archive tag now; scoping forget is the other half of not deciding another
    # host's retention from here.
    # 稼働中のデータベースをファイルとしてコピーしても、復元できる保証が無い。
    # 移行手順書にも「稼働中の postgres/couchdb をコピーすると壊れた状態で取れる」と
    # 書いてあるのに、日々のバックアップは同じことをしていた。転送は毎日成功して
    # いるが、そこから DB を戻せるかは別の話。
    #
    # そこで取得前に整合の取れたダンプを /var/lib 配下に吐き、それを本体と一緒に
    # 拾わせる。上の paths には Dawarich の PGDATA そのものも入っているが、**復元は
    # このダンプから行うこと**。生の PGDATA は稼働中のコピーなので起動する保証がない。
    #
    # 対象に入れていないもの:
    #   attic  — DB を戻してもキャッシュ本体 (/srv、対象外) が無いと意味がない。作り直す
    #   couchdb — 追記のみの形式で、稼働中のファイルコピーが公式に安全とされている
    backupPrepareCommand = ''
      set -eu
      umask 077
      rm -rf /var/lib/db-dumps
      install -d -m 0700 /var/lib/db-dumps

      ${pkgs.podman}/bin/podman exec dawarich_db \
        sh -c 'pg_dump -U "$POSTGRES_USER" -Fc dawarich_production' \
        > /var/lib/db-dumps/dawarich.dump

      ${pkgs.podman}/bin/podman exec miniflux-db \
        sh -c 'pg_dump -U "$POSTGRES_USER" -Fc miniflux' \
        > /var/lib/db-dumps/miniflux.dump

      # sqlite は WAL の途中でコピーすると千切れる。iterdump はトランザクション内で
      # 読むので、稼働中でも一貫した SQL が出る。1行で書くのは、nix の indented
      # string と nixfmt が複数行 Python のインデントを壊すため。
      ${pkgs.podman}/bin/podman exec paperless \
        python3 -c 'import sqlite3,sys; sys.stdout.writelines(l+"\n" for l in sqlite3.connect("/usr/src/paperless/data/db.sqlite3").iterdump())' \
        > /var/lib/db-dumps/paperless.sql

      # readeck も sqlite。paperless と違ってコンテナが Go の最小イメージで python3 も
      # sqlite3 も入っていないので、ホスト側から bind mount 先のファイルを直接読む。
      # .backup はオンラインバックアップ API を使うので、稼働中でも千切れない。
      # 初回 rebuild 時にはまだファイルが無いため、無ければ黙って飛ばす (ここで
      # 失敗させるとバックアップ全体が落ちる)。
      if [ -e /var/lib/homelab/readeck/data/db.sqlite3 ]; then
        ${pkgs.sqlite}/bin/sqlite3 /var/lib/homelab/readeck/data/db.sqlite3 \
          ".backup /var/lib/db-dumps/readeck.db"
      fi
    '';

    # ダンプは取得のあいだだけ存在すればよい。置きっぱなしにすると二重に容量を食う
    # うえ、古いダンプが正本のように見えてしまう。
    backupCleanupCommand = ''
      rm -rf /var/lib/db-dumps
    '';

    pruneOpts = resticCommon.retentionArgs ++ [ "--host homeserver" ];
    extraBackupArgs = [ "--tag homeserver" ];
    timerConfig = {
      OnCalendar = "03:00";
      # The Mac writes to the same repository; restic locks, so a fixed hour on
      # both sides just means one of them waits.
      RandomizedDelaySec = "30m";
      Persistent = true;
    };
  };

  # services.restic.backups builds its own wrapper, so nothing puts restic or
  # rclone on the interactive PATH. That is fine until the day the backup is
  # needed, which is the worst moment to discover that looking inside it starts
  # with `nix shell`. Restoring by hand also needs the same rclone the unit uses,
  # not whatever version a shell happens to fetch.
  environment.systemPackages = [
    pkgs.restic
    pkgs.rclone
  ];

  # Known failure mode worth remembering: the rclone Google Drive token expires
  # after roughly a week of disuse and both hosts then fail silently.
  #
  # 「fail silently」がそのまま放置されていた。このユニットには OnFailure が無く、
  # 上の方に書いてある「gatus already answers "did it run"」は事実ではない。gatus の
  # エンドポイントは homeserver.nix の sites 表からしか生えず、実際に生成される27件は
  # 全部 HTTP の死活監視で、バックアップに触れるものは一つも無い。母艦側
  # (home/restic-backup.nix) は ntfy へ投げているので、無防備なのはこのホストだけだった。
  #
  # 保留の理由は「ntfy の token が sops 管理で、このホストの age 鍵待ち」と書いてあったが、
  # 待つ必要はなかった。同じ topic と token は gatus が読んでいる gatus.env に既にあり、
  # 新しい秘密を置かずに済む。age 鍵を作って sops へ移すのはそれとして進めればよく、
  # そのときはここの EnvironmentFile を差し替えるだけになる。
  #
  # 制約として、ntfy はこの箱の中にいるので箱ごと落ちたときは飛ばない。これは gatus と
  # 同じ穴で、そちらは Pi が二つ目の目になっている。バックアップの失敗は箱が生きている
  # 前提で起きるので、ここでは実害にならない。
  #
  # 拾えないものも書いておく。これは「走って失敗した」を拾う仕組みなので、タイマーが
  # そもそも発火しなくなった場合は沈黙したままになる。そこまで見るなら死人スイッチが要る。
  systemd.services."ntfy-failure@" = {
    description = "Notify ntfy that %i failed";
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = "/var/lib/secrets/gatus.env";
      # %i は失敗したユニット名。OnFailure 側が %n で渡す。
      ExecStart = "${pkgs.writeShellScript "ntfy-failure" ''
        set -u
        unit="$1"
        # 本文に直近のログを入れる。通知だけ来ても結局 ssh する羽目になるため。
        body="$(${pkgs.systemd}/bin/journalctl -u "$unit" -n 20 --no-pager -o cat 2>&1 || true)"
        ${pkgs.curl}/bin/curl -fsS --max-time 15 \
          -H "Authorization: Bearer $NTFY_TOKEN" \
          -H "Title: $unit failed on homeserver" \
          -H "Priority: high" \
          -H "Tags: rotating_light" \
          -d "$body" \
          "http://127.0.0.1:8082/$NTFY_TOPIC" >/dev/null
      ''} %i";
    };
  };

  systemd.services."restic-backups-homeserver" = {
    onFailure = [ "ntfy-failure@%n.service" ];
  };
}
