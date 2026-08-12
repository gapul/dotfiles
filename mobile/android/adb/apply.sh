#!/usr/bin/env bash
# settings.conf / debloat.txt に宣言した Android の OS 設定を adb で適用する。
#
#   ./apply.sh            # 差分を出してから適用
#   ./apply.sh --dry-run  # 差分を出すだけ
#
# 現在値と一致している行は飛ばすので、何度流しても同じ結果になる。
set -euo pipefail

cd "$(dirname "$0")"

dry_run=false
[[ ${1:-} == "--dry-run" ]] && dry_run=true

if ! command -v adb >/dev/null; then
  echo "adb が無い: nix shell nixpkgs#android-tools で入れて再実行" >&2
  exit 1
fi

# 端末が 1 台だけ繋がっていることを確かめる。複数あると adb が
# どれに流すか決められず、意図しない端末を書き換えかねない。
devices=$(adb devices | awk 'NR>1 && $2=="device" {print $1}')
count=$(printf '%s' "$devices" | grep -c . || true)
if [[ $count -ne 1 ]]; then
  echo "USB デバッグ有効な端末をちょうど 1 台だけ繋いでください (今: ${count} 台)" >&2
  exit 1
fi
echo "対象: $devices"

changed=0

echo "━━━ settings ━━━"
while read -r ns key val; do
  [[ -z ${ns:-} || $ns == \#* ]] && continue
  current=$(adb shell settings get "$ns" "$key" </dev/null | tr -d '\r')
  if [[ $current == "$val" ]]; then
    continue
  fi
  echo "  $ns.$key: $current -> $val"
  changed=$((changed + 1))
  $dry_run || adb shell settings put "$ns" "$key" "$val" </dev/null
done <settings.conf

echo "━━━ debloat ━━━"
# インストール済みパッケージを 1 回だけ引いて、消す対象が残っているかを見る。
# ループ内の adb には </dev/null が要る。付けないと adb shell が
# ループの stdin (宣言ファイル) を読み尽くして行が飛ぶ。
installed=$(adb shell pm list packages --user 0 | tr -d '\r' | sed 's/^package://')
while read -r pkg _; do
  [[ -z ${pkg:-} || $pkg == \#* ]] && continue
  if ! grep -qx "$pkg" <<<"$installed"; then
    continue
  fi
  echo "  uninstall: $pkg"
  changed=$((changed + 1))
  $dry_run || adb shell pm uninstall -k --user 0 "$pkg" </dev/null || echo "    失敗 (システム必須の可能性): $pkg"
done <debloat.txt

if [[ $changed -eq 0 ]]; then
  echo "差分なし"
elif $dry_run; then
  echo "${changed} 件の差分 (--dry-run なので適用していない)"
else
  echo "${changed} 件を適用した"
fi
