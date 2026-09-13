#!/usr/bin/env bash
# journald を追いかけて、壊れたときの合図を ntfy に流す。
#
# 収集そのものは要らない。全コンテナが log-driver=journald なので、ログは既に
# 1 箇所に集まっている。足りないのは「誰も見に行かない」ことの方で、
# 2026-08-16 に見つかった 6 件はどれも何日もログに書かれ続けていた。
#
# 誤検知で鳴り続けると読まなくなるので、拾うのは「放置すると壊れたままになる」
# ものだけに絞る。単発の ERROR は拾わない。
set -uo pipefail

TOKEN_FILE=/var/lib/secrets/ntfy-alerts.token
NTFY_URL=http://127.0.0.1:8082/alerts

notify() {
  local title="$1" body="$2" prio="${3:-default}"
  curl -s -m 10 -o /dev/null \
    -H "Authorization: Bearer $(cat "$TOKEN_FILE")" \
    -H "Title: $title" -H "Priority: $prio" -H "Tags: warning" \
    -d "$body" "$NTFY_URL" || true
}

# 直らないものを 15 分おきに鳴らし続けない。
#
# 2026-09-13 に nixos-upgrade.service が failed のまま残り、この 1 件で 7 時間に
# 28 通鳴った。次の upgrade が走るまで failed は消えないので、検知は正しいのに
# 通知としては壊れている。読まなくなれば、隣に並んだ本物も見えなくなる。
#
# 状態が変わったら即座に鳴らす。変わらないなら 6 時間に 1 回まで。
# 直ったら記録を消して、再発は待たずに鳴らす。
STATE_DIR="${STATE_DIRECTORY:-/var/lib/journal-alert}"
REPEAT_AFTER=21600

mkdir -p "$STATE_DIR"

notify_once() {
  local key="$1" fingerprint="$2" title="$3" body="$4" prio="${5:-default}"
  local file="$STATE_DIR/$key" prev_at=0 prev_fp="" now
  now=$(date +%s)

  if [ -r "$file" ]; then
    IFS=$'\t' read -r prev_at prev_fp < "$file" || true
  fi

  if [ "$fingerprint" = "$prev_fp" ] && [ "$((now - ${prev_at:-0}))" -lt "$REPEAT_AFTER" ]; then
    return 0
  fi

  printf '%s\t%s\n' "$now" "$fingerprint" > "$file"
  notify "$title" "$body" "$prio"
}

# 合図が消えたことを記録する。次に出たときは 6 時間を待たずに鳴る。
clear_once() {
  rm -f "$STATE_DIR/$1"
}

# 拾う合図。左が journald の検索語、右が通知の見出し。
# grep -F の固定文字列で見る (正規表現にすると誤爆が増える)。
declare -a PATTERNS=(
  "Activating recovery mode|Home Assistant が recovery mode に落ちた"
  "stale sessions detected|free-games-claimer のストアセッションが切れた"
  "refusing to access private network|miniflux が自前 RSSHub を読めていない"
  "Failed to establish secure session|Matter のペアリングに失敗している"
  "Discovery timed out|Matter がデバイスを見つけられない"
  "permission denied|権限まわりで拒否されている"
  # 2026-08-24 に足した分。どれもこの日に実際に起きて、誰も気付かなかったもの。
  # podman は bind mount の元ディレクトリを作らないので、新しいスタックを足すと
  # ここで止まる。rebuild ごと exit 4 になるが、ログを見なければ分からない。
  "no such file or directory|コンテナの bind mount 先が無い"
  # restart を繰り返して systemd が諦めた状態。ユニットは failed のままになる。
  # ただしこれは「諦めた」ときにしか出ない。諦めずに回り続ける方は下で別に見る。
  "Start request repeated too quickly|再起動を繰り返して止まった"
  # tmpfiles が uid の食い違いで配下の作成を拒否する。移行の残骸で出る。
  "unsafe path transition|tmpfiles が所有者の食い違いで作成を拒否した"
  # Lazy containers may exit 137 when Podman finishes an intentional stop with
  # SIGKILL. Systemd accepts that transition; a real memory kill is still
  # unambiguous in the kernel's journal and must remain visible.
  "oom-kill|メモリ不足でプロセスが強制終了された"
)

SINCE="${1:--15min}"

# journald は 1 回だけ読む。パターンごとに読み直すと、パターンを増やすたびに
# 走査回数が倍々に増える (9 個で 18 回。12 時間分だと数分かかった)。
SNAP=$(mktemp)
# 今回暴れていたユニット。下の while はパイプの中で回るので、外に持ち出すには
# 変数ではなくファイルが要る。
LOOPING=$(mktemp)
trap 'rm -f "$SNAP" "$LOOPING"' EXIT
journalctl --since "$SINCE" --no-pager > "$SNAP" 2>/dev/null

for entry in "${PATTERNS[@]}"; do
  needle="${entry%%|*}"
  label="${entry#*|}"
  # 状態キーは検索語から作る。見出しは日本語なのでファイル名に向かない。
  key="pattern-$(printf '%s' "$needle" | tr -c 'A-Za-z0-9' '-')"
  hits=$(grep -cF "$needle" "$SNAP")
  if [ "${hits:-0}" -gt 0 ]; then
    sample=$(grep -F "$needle" "$SNAP" | tail -1 | cut -c1-200)
    # 件数は毎回変わるので指紋に入れない。入れると間引きが効かなくなる。
    notify_once "$key" "$needle" "$label" "直近 ${SINCE#-} で ${hits} 件
${sample}" high
  else
    clear_once "$key"
  fi
done

# 同じユニットが何度も失敗し続けている状態。
#
# これが無くて 2026-08-28 の romm-db を 2 日間見逃した。tc.log が壊れて MariaDB が
# 毎回 abort していたのに、Restart=always で回り続けたので systemd は諦めず、
# 上の "Start request repeated too quickly" も --failed も一度も引っかからなかった。
# journald には 5948 件の失敗が並んでいた。
#
# 諦めたものは failed になるので捕まる。捕まらないのは諦めずに壊れ続ける方で、
# 稼働中に見えるぶんこちらの方が長く放置される。
# 5 回。deploy で数回失敗するのは普通なので、そこは鳴らさない。
# 壊れて回り続けるものは桁が違う (romm-db は 28 分で 200 回だった)。
LOOP_THRESHOLD=5
grep -oE '[A-Za-z0-9@_.-]+\.service: Failed with result' "$SNAP" |
  sed 's/: Failed with result$//' | sort | uniq -c | sort -rn |
  while read -r count unit; do
    [ "${count:-0}" -lt "$LOOP_THRESHOLD" ] && continue
    # podman が内部で作る 16 進名のユニット (64桁-16桁) は中身を指さないので飛ばす。
    # glob だと attic-db.service のような普通の名前まで巻き込むので、桁数で見る。
    [[ "$unit" =~ ^[0-9a-f]{64}-[0-9a-f]{16}\.service$ ]] && continue
    sample=$(grep -F "$unit" "$SNAP" | grep -viF 'Failed with result' | tail -1 | cut -c1-200)
    echo "loop-$unit" >> "$LOOPING"
    notify_once "loop-$unit" "$unit" "$unit が失敗を繰り返している" "直近 ${SINCE#-} で ${count} 回失敗。稼働中に見えても中身は起動できていない。
${sample}" high
  done

# 収まったユニットの記録は消す。残したままだと、6 時間以内に暴れ直したときに
# 間引きに引っかかって黙る。これは 2026-08-28 の romm-db のような、
# 直ったように見えて再発する壊れ方をちょうど取りこぼす。
for state in "$STATE_DIR"/loop-*; do
  [ -e "$state" ] || continue
  grep -qxF "$(basename "$state")" "$LOOPING" 2>/dev/null || rm -f "$state"
done

# 落ちたユニット。systemd が知っているのに誰も見ていない典型。
#
# 2026-08-30 に 3 日で 26 回鳴っていて、しかも本文が "●" だけだった。原因が 2 つ:
#
#   1. --no-legend でも先頭の状態マーク "●" は消えないので、awk '{print $1}' が
#      ユニット名ではなくマークを拾っていた。名前が出ないので通知として無意味。
#   2. podman が healthcheck ごとに作る使い捨てユニット (64桁-16桁の 16 進名) が
#      DB の起動待ちなどで普通に失敗する。実害が無いのに毎回鳴るので、
#      本物が混ざっていても気付けなくなる。
#
# --plain でマークを外し、16 進の使い捨ては除く。再起動ループ検知と同じ判定。
failed=$(
  systemctl --failed --no-legend --plain --no-pager 2>/dev/null |
    awk '{print $1}' |
    grep -vE '^[0-9a-f]{64}-[0-9a-f]{16}\.service$' |
    tr '\n' ' '
)
if [ -n "${failed// /}" ]; then
  # 顔ぶれが変わったら鳴らす。同じままなら 6 時間に 1 回。
  notify_once "failed-units" "$failed" "failed unit がある" "$failed" high
else
  clear_once "failed-units"
fi

# restic の鮮度。転送が黙って止まるのはこの構成で実績がある
# (rclone の Google Drive トークンが 1 週間で失効する)。
if systemctl is-failed --quiet restic-backups-homeserver.service; then
  notify_once "restic" "failed" "restic のバックアップが失敗している" \
    "systemctl status restic-backups-homeserver" high
else
  clear_once "restic"
fi
