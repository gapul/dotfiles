#!/usr/bin/env bash
# バックアップから実際に復元してみる。月に1回。
#
# restic は毎日成功していて、check も通っている。それでも「戻せるか」は別の話で、
# 2026-08 に見つかったのがまさにそれだった — 稼働中の postgres をファイルとして
# コピーしていて、転送は毎日成功していたが復元できる保証が無かった。
#
# 直したあと、その直し自体は一度も検証していない。ダンプが入っていることは
# スナップショットの中身を見れば分かるが、それは「ファイルがある」であって
# 「復元できる」ではない。ここでやるのは後者。
#
# 使い捨ての postgres を立てて本当に pg_restore し、テーブルが生えたかを数える。
# 壊れたダンプ・途中で切れたダンプ・バージョン不一致は、ここで初めて落ちる。
set -uo pipefail

WORK=/var/lib/restore-drill
TOKEN_FILE=/var/lib/secrets/ntfy-alerts.token
NTFY_URL=http://127.0.0.1:8082/alerts
DB_CTR=restore-drill-db
MYSQL_CTR=restore-drill-mariadb
FAILURES=()

notify() {
  local title="$1" body="$2" prio="${3:-default}"
  curl -s -m 10 -o /dev/null \
    -H "Authorization: Bearer $(cat "$TOKEN_FILE")" \
    -H "Title: $title" -H "Priority: $prio" -H "Tags: floppy_disk" \
    -d "$body" "$NTFY_URL" || true
}

cleanup() {
  podman rm -f "$DB_CTR" >/dev/null 2>&1 || true
  podman rm -f "$MYSQL_CTR" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

fail() {
  FAILURES+=("$1")
  echo "NG: $1"
}

rm -rf "$WORK"
mkdir -p "$WORK"

# ── 1. スナップショットから取り出す ──────────────────────────
# Drive API の一時エラーで月次訓練が落ちても、以前は出力を /dev/null に捨てていたため
# 「戻せない」のか「その瞬間だけ読めない」のか判別できなかった。3回だけ再試行し、
# 最後の失敗理由を journal に残す。復元先は毎回空にして部分復元を混ぜない。
restore_log="$WORK/restic-restore.log"
restored=false
for attempt in 1 2 3; do
  rm -rf "${WORK:?}/var"
  if restic restore latest --host "$(hostname -s)" \
    --include /var/lib/db-dumps --target "$WORK" >"$restore_log" 2>&1; then
    restored=true
    break
  fi
  echo "restic restore attempt $attempt/3 failed" >&2
  [ "$attempt" -lt 3 ] && sleep $((attempt * 10))
done
if [ "$restored" != true ]; then
  echo "restic restore failed after 3 attempts:" >&2
  tail -n 30 "$restore_log" >&2
  notify "復元訓練: スナップショットを取り出せない" \
    "restic restore が失敗した。バックアップから戻せない状態かもしれない" high
  exit 1
fi

DUMPS="$WORK/var/lib/db-dumps"
for f in dawarich.dump miniflux.dump matrix-synapse.dump atuin.dump rallly.dump \
  spliit.dump romm.sql paperless.sql readeck.db forgejo.db navidrome.db \
  vaultwarden.db pingvin-share.db calnode.db jellyfin.db bambuddy.db \
  ntfy-user.db ntfy-cache.db home-assistant.db archivebox.db \
  matrix-discord.db matrix-telegram.db matrix-twitter.db matrix-meta.db \
  filestash-workflow.db filestash-metadata.db filestash-share.db; do
  [ -s "$DUMPS/$f" ] || fail "$f がスナップショットに無い (または空)"
done

# ── 2. 使い捨ての postgres に本当に流し込む ──────────────────
# 本番と同じイメージを使う。素の postgres:17 では dawarich が復元できない。
# あちらは PostGIS を使っていて (postgis / postgis_topology /
# postgis_tiger_geocoder / fuzzystrmatch / pgcrypto)、拡張の無いサーバでは
# pg_restore が落ちる。実際に落ちた — 訓練を入れて最初の一回で見つかった穴。
#
# miniflux は 16 だが、こちらのイメージ (17) に流し込める。pg_restore は前方には
# 流せる。逆 — 新しいダンプを古いサーバへ — は落ちる。
podman rm -f "$DB_CTR" >/dev/null 2>&1 || true
if podman run -d --name "$DB_CTR" \
  -e POSTGRES_PASSWORD=drill \
  -v "$DUMPS:/dumps:ro" \
  docker.io/postgis/postgis:17-3.5-alpine >/dev/null 2>&1; then

  # -h 127.0.0.1 が要る。公式イメージは初期化用に一時的なサーバを立てて、
  # 終わったら一度落として本番用に起動し直す。ソケット越しの pg_isready は
  # その一時サーバにも応答するので、そこへ繋ぐと COPY の途中で再起動に
  # 巻き込まれて "server closed the connection unexpectedly" になる。実際になった。
  # 初期化中は listen_addresses が空で TCP を開かないので、TCP で見れば
  # 本番用の起動だけを待てる。
  for i in $(seq 1 60); do
    podman exec "$DB_CTR" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1 && break
    [ "$i" -eq 60 ] && fail "使い捨て postgres が起動しなかった"
    sleep 2
  done

  # matrix-synapse はブリッジで取り込んだ過去ログが入る。相手のネットワークから
  # 取り直せるとは限らない (Signal の履歴は端末にしか無い) ので、戻せることを
  # 毎回確かめる対象に入れる。
  for db in dawarich miniflux matrix-synapse atuin rallly spliit; do
    [ -s "$DUMPS/$db.dump" ] || continue
    # 識別子は必ず引用する。matrix-synapse のようにハイフンを含む名前だと
    # 引用なしの CREATE DATABASE drill_matrix-synapse は構文エラーになる。
    #
    # Synapse は C 以外の照合順序の DB を見つけると起動を拒否する。戻せても起動
    # しないなら復元できたことにならないので、本番と同じ条件で作る。dawarich の
    # PostGIS で踏んだのと同じ形の穴 (訓練の意味はここにある)。
    locale=""
    [ "$db" = "matrix-synapse" ] && locale=" TEMPLATE template0 LC_COLLATE 'C' LC_CTYPE 'C'"
    podman exec "$DB_CTR" psql -U postgres -qc \
      "CREATE DATABASE \"drill_$db\"$locale" >/dev/null 2>&1
    if ! podman exec "$DB_CTR" pg_restore -U postgres -d "drill_$db" \
      --no-owner --no-privileges "/dumps/$db.dump" >/dev/null 2>&1; then
      fail "$db: pg_restore が失敗した"
      continue
    fi
    n=$(podman exec "$DB_CTR" psql -U postgres -d "drill_$db" -tAc \
      "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'" 2>/dev/null | tr -d ' ')
    if [ "${n:-0}" -lt 5 ]; then
      fail "$db: 復元後のテーブルが ${n:-0} 個しかない"
    else
      echo "OK: $db は ${n} テーブルで復元できた"
    fi
  done
else
  fail "使い捨て postgres を起動できなかった"
fi

# ── 3. MariaDB ───────────────────────────────────────────────
podman rm -f "$MYSQL_CTR" >/dev/null 2>&1 || true
if [ -s "$DUMPS/romm.sql" ] && podman run -d --name "$MYSQL_CTR" \
  -e MARIADB_ROOT_PASSWORD=drill \
  docker.io/library/mariadb:11 >/dev/null 2>&1; then
  for i in $(seq 1 60); do
    podman exec "$MYSQL_CTR" mariadb-admin -uroot -pdrill ping >/dev/null 2>&1 && break
    [ "$i" -eq 60 ] && fail "使い捨て MariaDB が起動しなかった"
    sleep 2
  done
  podman exec "$MYSQL_CTR" mariadb -uroot -pdrill -e 'CREATE DATABASE romm' >/dev/null 2>&1
  if podman exec -i "$MYSQL_CTR" mariadb -uroot -pdrill romm \
    < "$DUMPS/romm.sql" >/dev/null 2>&1; then
    n=$(podman exec "$MYSQL_CTR" mariadb -N -uroot -pdrill romm -e \
      "SELECT count(*) FROM information_schema.tables WHERE table_schema='romm'" 2>/dev/null)
    [ "${n:-0}" -ge 5 ] || fail "romm: 復元後のテーブルが ${n:-0} 個しかない"
    [ "${n:-0}" -lt 5 ] || echo "OK: romm は ${n} テーブルで復元できた"
  else
    fail "romm: MariaDB への復元に失敗した"
  fi
elif [ -s "$DUMPS/romm.sql" ]; then
  fail "使い捨て MariaDB を起動できなかった"
fi

# ── 4. SQLite ────────────────────────────────────────────────
# paperless は SQL のテキスト、readeck は .backup で取った sqlite ファイルそのもの
# (コンテナが Go の最小イメージで python3 が無いため)。形が違うので確認も分ける。
if [ -s "$DUMPS/paperless.sql" ]; then
  if sqlite3 "$WORK/paperless-drill.db" < "$DUMPS/paperless.sql" 2>/dev/null; then
    n=$(sqlite3 "$WORK/paperless-drill.db" \
      "SELECT count(*) FROM sqlite_master WHERE type='table'" 2>/dev/null)
    if [ "${n:-0}" -lt 5 ]; then
      fail "paperless: 復元後のテーブルが ${n:-0} 個しかない"
    else
      echo "OK: paperless は ${n} テーブルで復元できた"
    fi
  else
    fail "paperless: sqlite に流し込めなかった"
  fi
fi

if [ -s "$DUMPS/readeck.db" ]; then
  # ファイルとして取れているので、開いて整合を見るだけでよい。
  if sqlite3 "$DUMPS/readeck.db" "PRAGMA integrity_check" 2>/dev/null | grep -q '^ok$'; then
    n=$(sqlite3 "$DUMPS/readeck.db" \
      "SELECT count(*) FROM sqlite_master WHERE type='table'" 2>/dev/null)
    if [ "${n:-0}" -lt 3 ]; then
      fail "readeck: テーブルが ${n:-0} 個しかない"
    else
      echo "OK: readeck は ${n} テーブルで整合が取れている"
    fi
  else
    fail "readeck: integrity_check が通らない"
  fi
fi

for db in forgejo navidrome vaultwarden pingvin-share calnode jellyfin bambuddy \
  ntfy-user ntfy-cache home-assistant archivebox matrix-discord matrix-telegram \
  matrix-twitter matrix-meta filestash-workflow filestash-metadata filestash-share; do
  file="$DUMPS/$db.db"
  [ -s "$file" ] || continue
  if sqlite3 "$file" "PRAGMA integrity_check" 2>/dev/null | grep -q '^ok$'; then
    n=$(sqlite3 "$file" "SELECT count(*) FROM sqlite_master WHERE type='table'" 2>/dev/null)
    if [ "${n:-0}" -lt 1 ]; then
      fail "$db: 復元後にテーブルが無い"
    else
      echo "OK: $db は ${n} テーブルで整合が取れている"
    fi
  else
    fail "$db: integrity_check が通らない"
  fi
done

# Gameyfin's H2 database is copied while the service is stopped.  H2 Recover
# walks every page and emits SQL; a truncated/corrupt copy fails here.
if [ -d "$DUMPS/gameyfin-db" ]; then
  cp -a "$DUMPS/gameyfin-db" "$WORK/gameyfin-db"
  if podman run --rm \
    -v "$WORK/gameyfin-db:/drill:rw" \
    --entrypoint sh ghcr.io/gameyfin/gameyfin:latest -lc \
    'h2=$(find /opt/gameyfin/lib -name "h2-*.jar" | head -1); java -cp "$h2" org.h2.tools.Recover -dir /drill' \
    >/dev/null 2>&1 && find "$WORK/gameyfin-db" -name '*.sql' -size +0c | grep -q .; then
    echo "OK: gameyfin の H2 DB を走査・展開できた"
  else
    fail "gameyfin: H2 DB の復元走査に失敗した"
  fi
else
  fail "gameyfin-db がスナップショットに無い"
fi

# ── 5. 結果 ──────────────────────────────────────────────────
if [ ${#FAILURES[@]} -gt 0 ]; then
  notify "復元訓練: 戻せないものがある" "$(printf '%s\n' "${FAILURES[@]}")" high
  exit 1
fi

# 成功も鳴らす。月1回なので五月蝿くならないし、鳴らないと訓練自体が
# 止まっていることに気付けない。
notify "復元訓練: 全部戻せた" "PostgreSQL / MariaDB / SQLite / H2 の全永続DBをスナップショットから復元して確認した" low
