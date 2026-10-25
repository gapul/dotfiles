#!/usr/bin/env bash
# devices/<codename>/root/ に宣言した root の層 (KernelSU モジュールと ksud feature) を
# 端末に当てる。os.sh と同じく、差分を出してから適用する。
#
#   ./root.sh            # 差分を出してから適用
#   ./root.sh --dry-run  # 差分を出すだけ
#
# モジュールの zip は nix が組み立てる (nix/mobile/android-root.nix、
# `nix build ./nix#android-root-<codename>`)。ここはその manifest.tsv の versionCode と、
# 端末の `ksud module list` を比べて、無いもの・違うものを `ksud module install` する。
# 宣言に無いモジュールは報告だけして消さない (EXTRA で落とさないのは apps.ts と同じ)。
#
# 端末側の操作は adb 越しの su で行う。KernelSU Next の ADB Root を有効にするか、
# Superuser で Shell に root を許可しておく。モジュールは再起動で有効になるが、
# 再起動はしない (使っている最中の端末を勝手に落とさない)。
set -euo pipefail

cd "$(dirname "$0")"
repo=$(cd ../.. && pwd)

dry_run=false
[[ ${1:-} == "--dry-run" ]] && dry_run=true

if ! command -v adb >/dev/null; then
  echo "adb が無い: nix shell nixpkgs#android-tools で入れて再実行" >&2
  exit 1
fi
# 端末が複数あると adb が流し先を決められない。ANDROID_SERIAL で選んであればそれに従う。
if [[ -z ${ANDROID_SERIAL:-} ]]; then
  count=$(adb devices | awk 'NR>1 && $2=="device"' | grep -c . || true)
  if [[ $count -ne 1 ]]; then
    echo "USB デバッグ有効な端末をちょうど 1 台だけ繋ぐか、ANDROID_SERIAL で選んでください (今: ${count} 台)" >&2
    exit 1
  fi
fi

# ループ内から呼ばれるので stdin を切る (os.sh と同じ理由)。
dev() { adb shell "$@" </dev/null | tr -d '\r'; }
asu() { dev su -c "'$*'"; }

codename=${ANDROID_PROFILE:-$(dev getprop ro.product.device)}
decl="devices/${codename}/root"
if [[ ! -d $decl ]]; then
  echo "${codename} には root の宣言が無い ($decl)" >&2
  exit 1
fi
echo "対象: ${codename}"

if [[ $(asu id) != uid=0* ]]; then
  echo "adb 越しに su が通らない。KernelSU Next で ADB Root を有効にするか、Superuser で Shell を許可する" >&2
  exit 1
fi

# ANDROID_ROOT_BUILD はテスト用の上書き (nix を呼ばずに組み立て済みの置き場を使う)。
build=${ANDROID_ROOT_BUILD:-$(nix build "${repo}/nix#android-root-${codename}" --no-link --print-out-paths)}

# ksud module list は整形済みの JSON で、1 行に 1 キーが出る。キーの順番はモジュールごとに
# 違うので、オブジェクトの閉じ括弧で id / versionCode / enabled を 1 行にまとめる。
installed=$(asu /data/adb/ksud module list | awk '
  /^ *\{/ { id = ""; vc = ""; en = "" }
  /"id":/ { id = $0; sub(/.*"id": *"/, "", id); sub(/".*/, "", id) }
  /"versionCode":/ { vc = $0; sub(/.*"versionCode": *"/, "", vc); sub(/".*/, "", vc) }
  /"enabled":/ { en = $0; sub(/.*"enabled": *"/, "", en); sub(/".*/, "", en) }
  /^ *\}/ && id != "" { print id "\t" vc "\t" en }')

changed=0
installed_any=false

echo "━━━ モジュール ━━━"
declared_ids=""
while IFS=$'\t' read -r id code version file; do
  [[ -z ${id:-} ]] && continue
  declared_ids+="${id}"$'\n'
  row=$(awk -F'\t' -v id="$id" '$1 == id' <<<"$installed")
  if [[ -n $row ]]; then
    have=$(cut -f2 <<<"$row")
    # versionCode は "010202" のように 0 埋めで書かれることがある。8 進数に読ませない。
    if [[ $((10#${have:-0})) -eq $((10#$code)) ]]; then
      [[ $(cut -f3 <<<"$row") == false ]] && echo "  無効化されている (触らない): $id"
      continue
    fi
    echo "  入れ替え: $id ${have} -> ${code} (${version})"
  else
    echo "  インストール: $id ${code} (${version})"
  fi
  changed=$((changed + 1))
  if ! $dry_run; then
    adb push "${build}/${file}" "/data/local/tmp/${file}" </dev/null >/dev/null
    # インストーラは unzip の行や set -x の跡を大量に吐く。成功したら捨て、失敗したときだけ末尾を見せる。
    if log=$(asu "/data/adb/ksud module install /data/local/tmp/${file} 2>&1"); then
      installed_any=true
    else
      echo "    失敗: $id" >&2
      tail -n 15 <<<"$log" | sed 's/^/      /' >&2
    fi
    asu "rm -f /data/local/tmp/${file}" >/dev/null
  fi
done <"${build}/manifest.tsv"

while IFS=$'\t' read -r id _; do
  [[ -z ${id:-} ]] && continue
  grep -qx "$id" <<<"$declared_ids" || echo "  EXTRA    $id (宣言に無い。消すかは人が決める)"
done <<<"$installed"

echo "━━━ ksud feature ━━━"
features_changed=false
while read -r name want; do
  [[ -z ${name:-} || $name == \#* ]] && continue
  # 知らない feature には ksud が非 0 で返す。set -e で止めずに UNSUPPORTED として報告する。
  current=$(asu "/data/adb/ksud feature get $name" | sed -n 's/^Value: //p' || true)
  if [[ -z $current ]]; then
    echo "  UNSUPPORTED  $name (この KernelSU には無い)"
    continue
  fi
  [[ $current == "$want" ]] && continue
  echo "  $name: $current -> $want"
  changed=$((changed + 1))
  if ! $dry_run; then
    asu "/data/adb/ksud feature set $name $want" >/dev/null
    features_changed=true
  fi
done <"${decl}/features.conf"
# set だけだと再起動で戻る。save で設定ファイルに書いて残す。
if $features_changed; then
  asu "/data/adb/ksud feature save" >/dev/null
fi

if [[ $changed -eq 0 ]]; then
  echo "差分なし"
elif $dry_run; then
  echo "${changed} 件の差分 (--dry-run なので適用していない)"
else
  echo "${changed} 件を適用した"
  if $installed_any; then
    echo "モジュールは再起動で有効になる: adb reboot"
  fi
fi
