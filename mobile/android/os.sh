#!/usr/bin/env bash
# os-settings.conf / os-debloat.txt / os-apps.tsv に宣言した Android の OS 設定を
# 適用する。母艦から adb 越しにも、端末の中 (Termux) からも同じファイルで走る。
#
#   ./os.sh            # 差分を出してから適用
#   ./os.sh --dry-run  # 差分を出すだけ
#
# 現在値と一致している行は飛ばすので、何度流しても同じ結果になる。
#
# 端末ごとの宣言が devices/<codename>/ にあれば、ro.product.device を見てそちらの 3 ファイルを
# 読む (無ければ最上位、つまりスマホの宣言)。ANDROID_PROFILE=<codename> で上書きできる。
#
# 端末の中から走らせると、ケーブルを繋がずに settings を当てられる (Termux に
# WRITE_SECURE_SETTINGS を一度 adb で与えておく。README 参照)。ただし debloat と
# アプリ個別は署名レベルの権限が要るので adb 経由でしか通らない。そこは黙って
# 飛ばさず、飛ばした理由を出す。
set -euo pipefail

cd "$(dirname "$0")"

dry_run=false
[[ ${1:-} == "--dry-run" ]] && dry_run=true

# Termux の uname は Android を返す。MOBILE_ON_DEVICE はテスト用の上書き。
on_device=false
if [[ ${MOBILE_ON_DEVICE:-} == 1 || $(uname -o 2>/dev/null) == "Android" ]]; then
  on_device=true
fi

if $on_device; then
  # 端末の中では adb を挟まない。stdin も自分のものなので付け替え不要。
  dev() { "$@"; }
  # 値をそのまま 1 引数として渡せる。
  arg() { printf '%s' "$1"; }
  echo "対象: この端末 (Termux)"
else
  if ! command -v adb >/dev/null; then
    echo "adb が無い: nix shell nixpkgs#android-tools で入れて再実行" >&2
    exit 1
  fi
  # 端末が 1 台だけ繋がっていることを確かめる。複数あると adb が
  # どれに流すか決められず、意図しない端末を書き換えかねない。
  # ANDROID_SERIAL で選んであれば adb がそれに流すので、台数は問わない。
  devices=${ANDROID_SERIAL:-$(adb devices | awk 'NR>1 && $2=="device" {print $1}')}
  count=$(printf '%s' "$devices" | grep -c . || true)
  if [[ $count -ne 1 ]]; then
    echo "USB デバッグ有効な端末をちょうど 1 台だけ繋ぐか、ANDROID_SERIAL で選んでください (今: ${count} 台)" >&2
    exit 1
  fi
  # ループ内から呼ばれるので stdin を切る。切らないと adb shell が
  # ループの stdin (宣言ファイル) を読み尽くして行が飛ぶ。
  dev() { adb shell "$@" </dev/null; }
  # adb shell は引数を空白でつないで端末のシェルにもう一度読ませるので、JSON の " や空白が
  # 剥がれる。値は端末のシェル向けに単一引用符で包んで渡す。
  arg() { printf "'%s'" "${1//\'/\'\\\'\'}"; }
  echo "対象: $devices"
fi

# 端末の中でも getprop は使える。テストの偽 adb や母艦の端末内モードでは何も返らず、
# 最上位の宣言になる。
codename=${ANDROID_PROFILE:-$(dev getprop ro.product.device 2>/dev/null | tr -d '\r' || true)}
decl=.
if [[ -n $codename && $codename != default && -d devices/$codename ]]; then
  decl=devices/$codename
elif [[ -n ${ANDROID_PROFILE:-} && $ANDROID_PROFILE != default ]]; then
  # 打ち間違いで最上位 (スマホ) の debloat や設定を別の端末に当てないよう、明示した名前は確かめる。
  echo "ANDROID_PROFILE=${ANDROID_PROFILE} の宣言が無い (devices/${ANDROID_PROFILE})" >&2
  exit 1
fi
echo "宣言: $decl"

changed=0

echo "━━━ settings ━━━"
while read -r ns key val; do
  [[ -z ${ns:-} || $ns == \#* ]] && continue
  current=$(dev settings get "$ns" "$key" | tr -d '\r')
  if [[ $current == "$val" ]]; then
    continue
  fi
  echo "  $ns.$key: $current -> $val"
  changed=$((changed + 1))
  $dry_run || dev settings put "$ns" "$key" "$(arg "$val")"
done <"$decl/os-settings.conf"

echo "━━━ debloat ━━━"
if $on_device; then
  # pm uninstall は DELETE_PACKAGES (署名レベル) が要る。adb の shell uid だから
  # 通るのであって、アプリの uid には与えられない。
  echo "  スキップ (端末内からは権限が無い。母艦から adb 経由で流す)"
else
  # インストール済みパッケージを 1 回だけ引いて、消す対象が残っているかを見る。
  installed=$(adb shell pm list packages --user 0 | tr -d '\r' | sed 's/^package://')
  while read -r pkg _; do
    [[ -z ${pkg:-} || $pkg == \#* ]] && continue
    if ! grep -qx "$pkg" <<<"$installed"; then
      continue
    fi
    echo "  uninstall: $pkg"
    changed=$((changed + 1))
    $dry_run || adb shell pm uninstall -k --user 0 "$pkg" </dev/null || echo "    失敗 (システム必須の可能性): $pkg"
  done <"$decl/os-debloat.txt"
fi

echo "━━━ アプリ個別 ━━━"
if $on_device; then
  # set-home-activity / pm grant / deviceidle はどれも adb の shell uid 前提。
  echo "  スキップ (端末内からは権限が無い。母艦から adb 経由で流す)"
else
  # 現在値を 1 回だけ引いておく。行ごとに dumpsys を叩くと端末との往復が
  # 宣言の行数だけ増えて、体感で数十秒変わる。
  idle_whitelist=$(adb shell dumpsys deviceidle whitelist </dev/null | tr -d '\r')
  current_home=$(adb shell cmd package resolve-activity --brief -c android.intent.category.HOME </dev/null | tr -d '\r' | tail -1)
  while IFS=$'\t' read -r action pkg arg; do
    [[ -z ${action:-} || $action == \#* ]] && continue
    case "$action" in
    home)
      [[ $current_home == "${pkg}/${arg}" ]] && continue
      echo "  既定ランチャー: $current_home -> ${pkg}/${arg}"
      $dry_run || adb shell cmd package set-home-activity "${pkg}/${arg}" </dev/null
      ;;
    role)
      # 標準アプリ (ブラウザ、SMS など)。ブラウザのような排他ロールは、足すと前の持ち主が外れる。
      holders=$(adb shell cmd role get-role-holders --user 0 "$arg" </dev/null | tr -d '\r')
      grep -qx "$pkg" <<<"$holders" && continue
      echo "  標準アプリ ${arg##*.}: ${holders:-なし} -> $pkg"
      $dry_run || adb shell cmd role add-role-holder --user 0 "$arg" "$pkg" </dev/null
      ;;
    battery)
      grep -q ",$pkg," <<<",${idle_whitelist//$'\n'/,}," && continue
      echo "  電池最適化から除外: $pkg"
      $dry_run || adb shell dumpsys deviceidle whitelist "+$pkg" </dev/null >/dev/null
      ;;
    grant | revoke)
      # 現在値の照会は dumpsys の出力を解析する必要があって脆いので、そのまま流す。
      # grant / revoke はどちらも冪等 (同じ状態に再実行しても変化しない)。
      # ponytail: 差分表示なしで毎回発行している。うるさくなったら dumpsys package の
      # runtime permissions ブロックを解析して現在値と比べる
      echo "  ${action}: $pkg $arg"
      $dry_run || adb shell pm "$action" "$pkg" "$arg" </dev/null || echo "    失敗 (端末が持たない権限): $arg"
      ;;
    appops)
      echo "  appops: $pkg $arg"
      # shellcheck disable=SC2086  # arg は "<op> <mode>" の 2 語で、分割させたい
      $dry_run || adb shell cmd appops set "$pkg" $arg </dev/null
      ;;
    *)
      echo "  不明な動作: $action ($pkg)" >&2
      ;;
    esac
    changed=$((changed + 1))
  done <"$decl/os-apps.tsv"
fi

if [[ $changed -eq 0 ]]; then
  echo "差分なし"
elif $dry_run; then
  echo "${changed} 件の差分 (--dry-run なので適用していない)"
else
  echo "${changed} 件を適用した"
fi
