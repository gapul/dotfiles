{ config, pkgs, ... }:
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
      # An ArchiveBox snapshot exists precisely because the original page may
      # disappear.  Treating it as re-downloadable defeated that purpose.
      "/srv/archivebox"
      # Dumps from the 3DS: cartridge and eShop titles, save data, the NAND backup and
      # the console-unique keys needed to decrypt any of it. Cartridges wear out and
      # the eShop re-download service can end, so none of this is re-obtainable.
      "/srv/games/3ds"
    ];
    exclude = [
      # Container images are re-pullable and would dominate the repository. The
      # volumes directory underneath is deliberately not excluded — that is data.
      "/var/lib/containers/storage/overlay"
      "/var/lib/containers/storage/overlay-images"
      "/var/lib/containers/storage/overlay-layers"
      "/var/lib/containers/cache"
      # Pingvin is a delivery cache. The source media stays in its project
      # directory and shares can be recreated with `hs share create`; backing up
      # both the uploaded copy and Pingvin's generated ZIP duplicates large files.
      # Keep its small SQLite database and the consistent dump prepared below.
      "/var/lib/homelab/pingvin-share/data/uploads"
      # Runtime scratch, regenerated on boot.
      "/var/lib/systemd/coredump"
    ];
    # The rest of /srv is not backed up. It holds media and the attic cache: large,
    # and either re-obtainable or already content-addressed. /srv/syncthing is a
    # copy of what the Mac holds and is backed up from there. Dawarich,
    # ArchiveBox and the 3DS dumps are the exceptions listed above. Check this
    # list again whenever a service is pointed at the big disk — that is how
    # location history went missing.

    # Copying a running database as files gives no guarantee it can be restored.
    # The migration runbook even says "copying a running postgres/couchdb captures a broken
    # state", yet the daily backup was doing exactly that. The transfer succeeds every day,
    # but whether the DB can be restored from it is a separate question.
    #
    # So before the snapshot, write a consistent dump under /var/lib and let it be picked up
    # along with everything else. The paths above also include Dawarich's PGDATA itself, but
    # **restore from this dump**. The raw PGDATA is a copy of a running database and is not
    # guaranteed to start.
    #
    # Not included:
    #   attic  — restoring the DB is pointless without the cache itself (/srv, excluded). Rebuild it
    #   couchdb — append-only format; copying its files while running is officially safe
    backupPrepareCommand = ''
      set -eu
      umask 077
      rm -rf /var/lib/db-dumps
      install -d -m 0700 /var/lib/db-dumps

      sqlite_backup() {
        src="$1"
        dst="$2"
        if [ -e "$src" ]; then
          ${pkgs.sqlite}/bin/sqlite3 "$src" ".timeout 30000" ".backup $dst"
        fi
      }

      start_for_backup() {
        unit="$1"
        marker="$2"
        rm -f "$marker"
        if ! ${pkgs.systemd}/bin/systemctl is-active --quiet "$unit"; then
          touch "$marker"
          ${pkgs.systemd}/bin/systemctl start "$unit"
        fi
      }

      wait_healthy() {
        container="$1"
        attempt=0
        while [ "$attempt" -lt 120 ]; do
          if ${pkgs.podman}/bin/podman healthcheck run "$container" >/dev/null 2>&1; then
            return 0
          fi
          attempt=$((attempt + 1))
          ${pkgs.coreutils}/bin/sleep 1
        done
        echo "$container did not become healthy before backup" >&2
        return 1
      }

      ${pkgs.podman}/bin/podman exec dawarich_db \
        sh -c 'pg_dump -U "$POSTGRES_USER" -Fc dawarich_production' \
        > /var/lib/db-dumps/dawarich.dump

      ${pkgs.podman}/bin/podman exec miniflux-db \
        sh -c 'pg_dump -U "$POSTGRES_USER" -Fc miniflux' \
        > /var/lib/db-dumps/miniflux.dump

      # These databases normally sleep with their HTTP frontends. Start only
      # the ones that were inactive, and leave markers so cleanup can restore
      # exactly the pre-backup state.
      start_for_backup podman-rallly-db.service /run/backup-started-rallly-db
      start_for_backup podman-spliit-db.service /run/backup-started-spliit-db
      start_for_backup podman-romm-db.service /run/backup-started-romm-db
      wait_healthy rallly-db
      wait_healthy spliit-db
      wait_healthy romm-db

      ${pkgs.podman}/bin/podman exec rallly-db \
        sh -c 'pg_dump -U "$POSTGRES_USER" -Fc "$POSTGRES_DB"' \
        > /var/lib/db-dumps/rallly.dump

      ${pkgs.podman}/bin/podman exec spliit-db \
        sh -c 'pg_dump -U "$POSTGRES_USER" -Fc "$POSTGRES_DB"' \
        > /var/lib/db-dumps/spliit.dump

      ${pkgs.podman}/bin/podman exec romm-db \
        sh -c 'mariadb-dump --single-transaction -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"' \
        > /var/lib/db-dumps/romm.sql

      # ネイティブの PostgreSQL (atuin が database.createLocally で生やしたクラスタ)。
      # コンテナ側と違ってここは見落としていた。/var/lib は paths に入っているので
      # PGDATA のファイルは restic に入るが、それは稼働中のコピーで、起動する保証が
      # 無い。このファイル自身が dawarich についてそう書いている。
      #
      # Matrix の履歴がここに溜まる。ブリッジで取り込んだ過去ログは相手の
      # ネットワークから取り直せるとは限らない (Signal は端末にしか無い) ので、
      # 壊れたコピーしか無い状態にはしない。
      ${pkgs.util-linux}/bin/runuser -u postgres -- \
        ${config.services.postgresql.package}/bin/pg_dump -Fc matrix-synapse \
        > /var/lib/db-dumps/matrix-synapse.dump

      ${pkgs.util-linux}/bin/runuser -u postgres -- \
        ${config.services.postgresql.package}/bin/pg_dump -Fc atuin \
        > /var/lib/db-dumps/atuin.dump

      # sqlite は WAL の途中でコピーすると千切れる。iterdump はトランザクション内で
      # 読むので、稼働中でも一貫した SQL が出る。1行で書くのは、nix の indented
      # string と nixfmt が複数行 Python のインデントを壊すため。
      # paperless sleeps too (lazy-http-services.nix); same start/marker dance as the
      # databases below. redis first, the app container depends on it.
      start_for_backup podman-paperless-redis.service /run/backup-started-paperless-redis
      start_for_backup podman-paperless.service /run/backup-started-paperless
      wait_healthy paperless
      ${pkgs.podman}/bin/podman exec paperless \
        python3 -c 'import sqlite3,sys; sys.stdout.writelines(l+"\n" for l in sqlite3.connect("/usr/src/paperless/data/db.sqlite3").iterdump())' \
        > /var/lib/db-dumps/paperless.sql

      # readeck も sqlite。paperless と違ってコンテナが Go の最小イメージで python3 も
      # sqlite3 も入っていないので、ホスト側から bind mount 先のファイルを直接読む。
      # .backup はオンラインバックアップ API を使うので、稼働中でも千切れない。
      # 初回 rebuild 時にはまだファイルが無いため、無ければ黙って飛ばす (ここで
      # 失敗させるとバックアップ全体が落ちる)。
      sqlite_backup /var/lib/homelab/readeck/data/db.sqlite3 /var/lib/db-dumps/readeck.db
      sqlite_backup /var/lib/homelab/forgejo/data/gitea/gitea.db /var/lib/db-dumps/forgejo.db
      sqlite_backup /var/lib/homelab/navidrome/data/navidrome.db /var/lib/db-dumps/navidrome.db
      sqlite_backup /var/lib/homelab/vaultwarden/data/db.sqlite3 /var/lib/db-dumps/vaultwarden.db
      sqlite_backup /var/lib/homelab/pingvin-share/data/pingvin-share.db /var/lib/db-dumps/pingvin-share.db
      sqlite_backup /var/lib/homelab/formera/formera.db /var/lib/db-dumps/formera.db
      sqlite_backup /var/lib/homelab/calnode/calnode.db /var/lib/db-dumps/calnode.db
      sqlite_backup /var/lib/gotosocial/database.sqlite /var/lib/db-dumps/gotosocial.db
      sqlite_backup /var/lib/writefreely/writefreely.db /var/lib/db-dumps/writefreely.db
      sqlite_backup /var/lib/nostr-rs-relay/nostr.db /var/lib/db-dumps/nostr-relay.db
      sqlite_backup /var/lib/private/puls/health.db /var/lib/db-dumps/health.db
      sqlite_backup /var/lib/homelab/homebox/homebox.db /var/lib/db-dumps/homebox.db
      sqlite_backup /var/lib/homelab/jellyfin/config/data/data/jellyfin.db /var/lib/db-dumps/jellyfin.db
      sqlite_backup /var/lib/homelab/bambuddy/data/bambuddy.db /var/lib/db-dumps/bambuddy.db
      sqlite_backup /var/lib/homelab/ntfy/lib/user.db /var/lib/db-dumps/ntfy-user.db
      sqlite_backup /var/lib/homelab/ntfy/cache/cache.db /var/lib/db-dumps/ntfy-cache.db
      sqlite_backup /var/lib/hass/home-assistant_v2.db /var/lib/db-dumps/home-assistant.db
      sqlite_backup /srv/archivebox/index.sqlite3 /var/lib/db-dumps/archivebox.db

      # LINE のログイン (アクセストークンと E2EE 鍵) もここにある。失うと再ログインで済むが、
      # ブリッジが Matrix 側に作った部屋との対応も一緒に消える。
      sqlite_backup /var/lib/matrix-line/matrix-line.db /var/lib/db-dumps/matrix-line.db

      for bridge in discord telegram twitter meta; do
        sqlite_backup "/var/lib/homelab/matrix/bridges/$bridge/mautrix-$bridge.db" \
          "/var/lib/db-dumps/matrix-$bridge.db"
        sqlite_backup "/var/lib/homelab/matrix/bridges/$bridge/db.db" \
          "/var/lib/db-dumps/matrix-$bridge.db"
      done

      for db in workflow metadata share; do
        sqlite_backup "/var/lib/homelab/filestash/state/db/$db.sql" \
          "/var/lib/db-dumps/filestash-$db.db"
      done

      # Gameyfin uses an embedded H2 database, for which an online file copy is
      # not consistent.  Stop only this catalogue long enough to copy its small
      # DB, then let backupCleanupCommand bring it back even if restic fails.
      if ${pkgs.systemd}/bin/systemctl is-active --quiet podman-gameyfin.service; then
        touch /run/gameyfin-stopped-for-backup
        ${pkgs.systemd}/bin/systemctl stop podman-gameyfin.service
      fi
      if [ -d /var/lib/homelab/gameyfin/db ]; then
        ${pkgs.coreutils}/bin/cp -a /var/lib/homelab/gameyfin/db /var/lib/db-dumps/gameyfin-db
      fi
    '';

    # The dumps only need to exist during the snapshot. Leaving them around doubles the space
    # used, and an old dump could be mistaken for the source of truth.
    backupCleanupCommand = ''
      rm -rf /var/lib/db-dumps
      for service in rallly-db spliit-db romm-db paperless paperless-redis; do
        marker="/run/backup-started-$service"
        if [ -e "$marker" ]; then
          rm -f "$marker"
          ${pkgs.systemd}/bin/systemctl stop "podman-$service.service"
        fi
      done
      if [ -e /run/gameyfin-stopped-for-backup ]; then
        rm -f /run/gameyfin-stopped-for-backup
        ${pkgs.systemd}/bin/systemctl start podman-gameyfin.service
      fi
    '';

    # pruneOpts is intentionally left empty. forget/prune on the shared repository is handled
    # only by the always-on Mac mini (home/macmini-backup.nix). If Homeserver also pruned right
    # after its backup, it would contend for the exclusive lock with the 05:00 Mac mini backup,
    # and the whole unit would fail even though the snapshot was saved.
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
  # The "fail silently" was simply left as is. This unit had no OnFailure, and the
  # "gatus already answers "did it run"" written further up is not true. gatus endpoints are
  # generated only from the sites table in homeserver.nix, and all 27 actually generated are
  # HTTP liveness checks; not one touches backups. The main Mac side
  # (home/restic-backup.nix) posts to ntfy, so this host was the only unprotected one.
  #
  # The stated reason for deferring was "the ntfy token is managed by sops and waits on this
  # host's age key", but there was no need to wait. The same topic and token are already in
  # gatus.env, which gatus reads, so no new secret is needed. Creating the age key and moving
  # to sops can proceed separately; when it does, only the EnvironmentFile here needs swapping.
  #
  # One limitation: ntfy lives in this box, so nothing is sent if the whole box goes down. That
  # is the same hole as gatus, where the Pi serves as a second pair of eyes. Backup failures
  # happen while the box is alive, so it does no real harm here.
  #
  # Also noting what this can't catch. It catches "ran and failed", so if the timer stops
  # firing altogether it stays silent. Covering that would need a dead man's switch.
  systemd.services."ntfy-failure@" = {
    description = "Notify ntfy that %i failed";
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = "/var/lib/secrets/gatus.env";
      # %i is the name of the failed unit. The OnFailure side passes it as %n.
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
