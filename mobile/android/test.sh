#!/usr/bin/env bash
# os.sh / apps.sh の自己チェック。偽の adb を PATH に置いて回すので実機は要らない。
#
# 見張っているのは 2 つ:
#   - ループの stdin。ループ内の adb から </dev/null を外すと adb が宣言ファイルを
#     読み尽くし、1 行目しか処理されずにここが落ちる。
#   - 宣言 vs 実機の突き合わせ。MISSING / EXTRA の判定と終了コード。
set -euo pipefail

cd "$(dirname "$0")"
stub=$(mktemp -d)
trap 'rm -rf "$stub"' EXIT
fail=0

# 端末に入っている体にするパッケージ: 宣言の 1 行目と、宣言に無いものを 1 つ。
# head を挟むと宣言が増えたとき grep が SIGPIPE で落ちて pipefail に引っかかる
kept=$(awk -F'\t' '$0 !~ /^[[:space:]]*(#|$)/ { print $1; exit }' apps.tsv)
declared_count=$(grep -cvE '^[[:space:]]*(#|$)' apps.tsv)

cat >"$stub/adb" <<EOF
#!/usr/bin/env bash
# 本物の adb shell は stdin を読み切るので、そこも真似る (これが無いと
# </dev/null の有無で挙動が変わらず、テストが素通りする)。
case "\$*" in
  devices) printf 'List of devices attached\nemulator-5554\tdevice\n' ;;
  "shell settings get "*)
    cat >/dev/null
    echo null
    ;;
  "shell pm list packages --user 0")
    cat >/dev/null
    echo "package:com.example.absent"
    ;;
  "shell pm list packages -3 --user 0")
    cat >/dev/null
    echo "package:${kept}"
    echo "package:com.example.undeclared"
    ;;
  "shell dumpsys deviceidle whitelist") cat >/dev/null ;;
  "shell cmd package resolve-activity --brief -c android.intent.category.HOME")
    cat >/dev/null
    echo "com.example.otherlauncher/.Home"
    ;;
  *) cat >/dev/null ;;
esac
EOF
chmod +x "$stub/adb"

# adopt は配布元を引いて経路を判定する。テストはネットワークに依存させたくないので、
# どちらの照会も「見つからない」を返させ、判定不能の枝に落とす。
# 端末内モード用。Android の settings コマンドを真似る。
cat >"$stub/settings" <<'SETTINGS'
#!/usr/bin/env bash
[[ $1 == get ]] && echo null
SETTINGS
chmod +x "$stub/settings"

printf '#!/usr/bin/env bash\nexit 1\n' >"$stub/fdroidcl"
printf '#!/usr/bin/env bash\nexit 1\n' >"$stub/curl"
chmod +x "$stub/fdroidcl" "$stub/curl"
export PATH="$stub:$PATH"

check() {
  local name=$1 want=$2 got=$3
  if [[ $want == "$got" ]]; then
    echo "ok: $name ($got)"
  else
    echo "FAIL: $name — 期待 $want / 実際 $got" >&2
    fail=1
  fi
}

# ── os.sh: 宣言した設定がひとつ残らず差分として出るか ────────────────────
# スクリプト自体の stdin は閉じる。ループの外の adb が端末の入力を待って
# 止まらないようにするためで、ループの中の stdin (宣言ファイル) には影響しない。
out_os=$(./os.sh --dry-run </dev/null)
out=$out_os
check "os.sh の設定差分" \
  "$(grep -cvE '^[[:space:]]*(#|$)' os-settings.conf)" \
  "$(grep -cE '^  (global|system|secure)\.' <<<"$out" || true)"

# ── apps.sh status: MISSING / EXTRA の判定と終了コード ───────────────────
out=$(./apps.sh status </dev/null) && status_rc=0 || status_rc=$?
check "apps.sh の MISSING 数" "$((declared_count - 1))" "$(grep -c MISSING <<<"$out" || true)"
check "apps.sh の EXTRA 数" "1" "$(grep -c EXTRA <<<"$out" || true)"
check "MISSING があれば exit 1" "1" "$status_rc"

# ── apps.sh obtainium: play 以外の全行が URL になるか ────────────────────
check "obtainium の URL 数" \
  "$(grep -vE '^[[:space:]]*(#|$)' apps.tsv | grep -cv $'\tplay\t')" \
  "$(./apps.sh obtainium 2>/dev/null | grep -c '^https://' || true)"

# ── os.sh: アプリ個別の宣言が適用対象として出るか ────────────────────────
check "既定ランチャーの差分" "1" "$(grep -c '既定ランチャー' <<<"$out_os" || true)"
check "電池最適化の除外数" \
  "$(grep -c $'^battery\t' os-apps.tsv || true)" \
  "$(grep -c '電池最適化から除外' <<<"$out_os" || true)"

# ── launcher-theme.py: Kvaesitso の形式を満たすか ────────────────────────
if ./launcher-theme.py --check >/dev/null 2>&1; then
  echo "ok: launcher-theme.py の形式"
else
  echo "FAIL: launcher-theme.py が Kvaesitso の形式を満たさない" >&2
  fail=1
fi

# ── apps.sh adopt: 宣言に無いものだけを tsv 行として出すか ────────────────
# 偽 adb は宣言済み 1 件 + 未宣言 1 件を返す。出るのは後者だけであるべき。
out=$(./apps.sh adopt 2>/dev/null || true)
check "adopt の行数" "1" "$(grep -c '^com.example.undeclared' <<<"$out" || true)"

# ── apps.sh aurora: play 行だけが Favourites になり、形式が Aurora の schema か ──
aurora=$(./apps.sh aurora)
check "aurora の favourites 数" \
  "$(grep -cE $'\tplay\t' apps.tsv || true)" \
  "$(python3 -c 'import json,sys; print(len(json.load(sys.stdin)["favourites"]))' <<<"$aurora")"
check "aurora の JSON が壊れていない" "ok" \
  "$(python3 -c 'import json,sys; d=json.load(sys.stdin); print("ok" if all({"packageName","displayName","iconURL","added","mode"} <= set(f) and f["mode"]=="IMPORT" for f in d["favourites"]) else "ng")' <<<"$aurora")"

# ── os.sh 端末内モード: settings は当てて、権限の要る節は理由付きで飛ばすか ──
out_local=$(MOBILE_ON_DEVICE=1 ./os.sh --dry-run </dev/null)
check "端末内でも設定差分は出る" \
  "$(grep -cvE '^[[:space:]]*(#|$)' os-settings.conf)" \
  "$(grep -cE '^  (global|system|secure)\.' <<<"$out_local" || true)"
check "権限の要る節は飛ばす" "2" "$(grep -c 'スキップ' <<<"$out_local" || true)"
check "端末内では adb を呼ばない" "0" "$(grep -c '既定ランチャー' <<<"$out_local" || true)"

exit "$fail"
