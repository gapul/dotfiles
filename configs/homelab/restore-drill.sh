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
if ! restic restore latest --host "$(hostname -s)" \
  --include /var/lib/db-dumps --target "$WORK" >/dev/null 2>&1; then
  notify "復元訓練: スナップショットを取り出せない" \
    "restic restore が失敗した。バックアップから戻せない状態かもしれない" high
  exit 1
fi

DUMPS="$WORK/var/lib/db-dumps"
for f in dawarich.dump miniflux.dump paperless.sql readeck.db; do
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

  for db in dawarich miniflux; do
    [ -s "$DUMPS/$db.dump" ] || continue
    podman exec "$DB_CTR" psql -U postgres -qc "CREATE DATABASE drill_$db" >/dev/null 2>&1
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

# ── 3. sqlite ────────────────────────────────────────────────
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

# ── 4. 結果 ──────────────────────────────────────────────────
if [ ${#FAILURES[@]} -gt 0 ]; then
  notify "復元訓練: 戻せないものがある" "$(printf '%s\n' "${FAILURES[@]}")" high
  exit 1
fi

# 成功も鳴らす。月1回なので五月蝿くならないし、鳴らないと訓練自体が
# 止まっていることに気付けない。
notify "復元訓練: 全部戻せた" "dawarich / miniflux / paperless / readeck をスナップショットから復元して確認した" low
