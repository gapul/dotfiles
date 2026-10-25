#!/usr/bin/env bash
# os.sh / apps.ts の自己チェック。偽の adb を PATH に置いて回すので実機は要らない。
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
  "shell settings put "*)
    cat >/dev/null
    # 端末のシェルに渡る文字列そのもの (adb は引数を空白でつなぐ) を記録する。
    [[ -n \${ADB_LOG:-} ]] && echo "\$*" >>"\$ADB_LOG"
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

# ── apps.ts status: MISSING / EXTRA の判定と終了コード ───────────────────
out=$(./apps.ts status </dev/null) && status_rc=0 || status_rc=$?
check "apps.ts の MISSING 数" "$((declared_count - 1))" "$(grep -c MISSING <<<"$out" || true)"
check "apps.ts の EXTRA 数" "1" "$(grep -c EXTRA <<<"$out" || true)"
check "MISSING があれば exit 1" "1" "$status_rc"

# ── apps.ts obtainium: play 以外の全行が URL になるか ────────────────────
check "obtainium の URL 数" \
  "$(grep -vE '^[[:space:]]*(#|$)' apps.tsv | grep -cv $'\tplay\t')" \
  "$(./apps.ts obtainium 2>/dev/null | grep -c '^https://' || true)"

# ── os.sh: アプリ個別の宣言が適用対象として出るか ────────────────────────
check "既定ランチャーの差分" "1" "$(grep -c '既定ランチャー' <<<"$out_os" || true)"
check "電池最適化の除外数" \
  "$(grep -c $'^battery\t' os-apps.tsv || true)" \
  "$(grep -c '電池最適化から除外' <<<"$out_os" || true)"

# ── launcher-theme.ts: Kvaesitso の形式を満たすか ────────────────────────
if ./launcher-theme.ts --check >/dev/null 2>&1; then
  echo "ok: launcher-theme.ts の形式"
else
  echo "FAIL: launcher-theme.ts が Kvaesitso の形式を満たさない" >&2
  fail=1
fi

# ── apps.ts adopt: 宣言に無いものだけを tsv 行として出すか ────────────────
# 偽 adb は宣言済み 1 件 + 未宣言 1 件を返す。出るのは後者だけであるべき。
out=$(./apps.ts adopt 2>/dev/null || true)
check "adopt の行数" "1" "$(grep -c '^com.example.undeclared' <<<"$out" || true)"

# ── apps.ts aurora: play 行だけが Favourites になり、形式が Aurora の schema か ──
aurora=$(./apps.ts aurora)
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

# ── 端末ごとの宣言: ANDROID_PROFILE で devices/nabu/ に切り替わるか ──────────
# 偽 adb が返す宣言済みの 1 件は最上位の宣言のもので、nabu の宣言には無い。
nabu=devices/nabu
nabu_count=$(grep -cvE '^[[:space:]]*(#|$)' "$nabu/apps.tsv")
out=$(ANDROID_PROFILE=nabu ./apps.ts status </dev/null) || true
check "nabu の宣言を読む" "1" "$(grep -c "宣言: $nabu/apps.tsv" <<<"$out" || true)"
check "nabu の MISSING 数" "$nabu_count" "$(grep -c MISSING <<<"$out" || true)"
out=$(ANDROID_PROFILE=nabu ./os.sh --dry-run </dev/null)
check "nabu の設定差分" \
  "$(grep -cvE '^[[:space:]]*(#|$)' "$nabu/os-settings.conf")" \
  "$(grep -cE '^  (global|system|secure)\.' <<<"$out" || true)"
# JSON の値は端末のシェルで剥がれないよう、単一引用符で包んで渡っているか。
adb_log="$stub/adb.log"
ADB_LOG=$adb_log ANDROID_PROFILE=nabu ./os.sh </dev/null >/dev/null
check "JSON の値は引用符付きで渡す" "1" \
  "$(grep -c "theme_customization_overlay_packages '{\"" "$adb_log" || true)"
check "宣言の無い端末は最上位を読む" "1" \
  "$(./os.sh --dry-run </dev/null | grep -c '^宣言: \.$' || true)"
if ANDROID_PROFILE=no-such-device ./os.sh --dry-run </dev/null >/dev/null 2>&1; then
  echo "FAIL: 宣言の無い ANDROID_PROFILE で os.sh が最上位の宣言に落ちた" >&2
  fail=1
else
  echo "ok: 宣言の無い ANDROID_PROFILE では止まる"
fi

# ── Material You の元の色が palettes.json の iris と揃っているか ─────────────
# 宣言は os-settings.conf に直に書いてある。palettes.json を変えたら、ここで落ちて気付く。
iris=$(python3 -c 'import json; d=json.load(open("../../configs/theme/palettes.json")); print(d["palettes"][d["active"]]["iris"].upper())')
for conf in os-settings.conf devices/*/os-settings.conf; do
  seed=$(sed -n 's/.*"android.theme.customization.system_palette":"\([0-9A-Fa-f]*\)".*/\1/p' "$conf")
  [[ -z $seed ]] && continue
  check "Material You の元の色 ($conf)" "$iris" "$seed"
done

# ── root.sh: モジュールの versionCode と ksud feature の差分 ─────────────────
# 端末には「同じ版」「古い版」「宣言に無い」の 3 つが入っていて、宣言の 1 つは入っていない
# 体にする。feature は宣言の 1 行目だけ値を外す。
rootstub=$(mktemp -d)
build=$(mktemp -d)
trap 'rm -rf "$stub" "$rootstub" "$build"' EXIT
printf 'same\t5\tv5\t01-same.zip\nold\t3\tv3\t02-old.zip\nabsent\t1\tv1\t03-absent.zip\n' >"$build/manifest.tsv"
first_feature=$(awk '$0 !~ /^[[:space:]]*(#|$)/ { print $1; exit }' "$nabu/root/features.conf")
first_value=$(awk '$0 !~ /^[[:space:]]*(#|$)/ { print $2; exit }' "$nabu/root/features.conf")
cat >"$rootstub/adb" <<EOF
#!/usr/bin/env bash
cat >/dev/null
case "\$*" in
  devices) printf 'List of devices attached\nemulator-5554\tdevice\n' ;;
  *"su -c 'id'"*) echo "uid=0(root) gid=0(root)" ;;
  *"ksud module list"*)
    printf '[\n  {\n    "id": "same",\n    "versionCode": "005",\n    "enabled": "true"\n  },\n'
    printf '  {\n    "versionCode": "2",\n    "id": "old",\n    "enabled": "true"\n  },\n'
    printf '  {\n    "id": "stray",\n    "versionCode": "1",\n    "enabled": "true"\n  }\n]\n'
    ;;
  *"ksud feature get ${first_feature}'"*) echo "Value: \$((1 - ${first_value}))" ;;
  # 本物の ksud は知らない feature に非 0 で返す。
  *"ksud feature get \${UNSUPPORTED_FEATURE:-none}'"*)
    echo "Error: Unknown feature" >&2
    exit 1
    ;;
  *"ksud feature get "*)
    # 宣言どおりの値を返す。features.conf を読んで、引数の feature の値を探す。
    name=\$(sed -E "s/.*feature get ([a-z_]+).*/\\1/" <<<"\$*")
    echo "Value: \$(awk -v n="\$name" '\$1 == n { print \$2 }' "$PWD/$nabu/root/features.conf")"
    ;;
esac
EOF
chmod +x "$rootstub/adb"
out=$(PATH="$rootstub:$PATH" ANDROID_PROFILE=nabu ANDROID_ROOT_BUILD=$build ./root.sh --dry-run </dev/null)
check "root: 同じ versionCode は触らない (0 埋めでも)" "0" "$(grep -c ': same' <<<"$out" || true)"
check "root: 古い版は入れ替え" "1" "$(grep -c '入れ替え: old 2 -> 3' <<<"$out" || true)"
check "root: 無いものはインストール" "1" "$(grep -c 'インストール: absent' <<<"$out" || true)"
check "root: 宣言に無いものは EXTRA" "1" "$(grep -c 'EXTRA    stray' <<<"$out" || true)"
check "root: feature の差分" "1" "$(grep -c "^  ${first_feature}: " <<<"$out" || true)"
check "root: 差分の総数" "1" "$(grep -c '^3 件の差分' <<<"$out" || true)"
last_feature=$(awk '$0 !~ /^[[:space:]]*(#|$)/ { name = $1 } END { print name }' "$nabu/root/features.conf")
out=$(PATH="$rootstub:$PATH" UNSUPPORTED_FEATURE=$last_feature ANDROID_PROFILE=nabu ANDROID_ROOT_BUILD=$build \
  ./root.sh --dry-run </dev/null) || true
check "root: 知らない feature は報告して続ける" "1" "$(grep -c "UNSUPPORTED  ${last_feature}" <<<"$out" || true)"
check "root: その後も最後まで走る" "1" "$(grep -c '件の差分' <<<"$out" || true)"
if PATH="$rootstub:$PATH" ANDROID_PROFILE=default ANDROID_ROOT_BUILD=$build ./root.sh --dry-run </dev/null >/dev/null 2>&1; then
  echo "FAIL: root の宣言が無い端末で root.sh が通った" >&2
  fail=1
else
  echo "ok: root の宣言が無い端末では止まる"
fi

exit "$fail"
