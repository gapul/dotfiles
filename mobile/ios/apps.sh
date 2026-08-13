#!/usr/bin/env bash
# apps.tsv に宣言したアプリと実機を突き合わせる。Android 側の apps.sh と同じ役割だが、
# iOS には入れる手段が無いので status と verify だけ。
#
#   ./apps.sh status   # USB 接続した iPhone と宣言の差分。MISSING があれば exit 1 (既定)
#   ./apps.sh verify   # appstore 行の bundleId が実在するか (iTunes Search API)
#
# status には USB 接続と、端末側で「このコンピュータを信頼」済みであることが要る。
# ネットワーク越しには照会できない。
set -euo pipefail

cd "$(dirname "$0")"

declared() { grep -vE '^[[:space:]]*(#|$)' apps.tsv; }

cmd_status() {
  if ! command -v ideviceinstaller >/dev/null; then
    echo "ideviceinstaller が無い: nix shell nixpkgs#ideviceinstaller (just ios-apps なら自動)" >&2
    exit 1
  fi

  # 出力は "bundleId, \"version\", \"name\"" の CSV で 1 行目がヘッダ。
  # bundleId だけ抜き、ヘッダ (CFBundleIdentifier) は落とす。
  local installed missing=0 extra=0
  installed=$(ideviceinstaller list | cut -d, -f1 | grep -v '^CFBundleIdentifier$' | sed 's/[[:space:]]*$//' | sort)

  echo "━━━ 宣言したが端末に無い ━━━"
  while IFS=$'\t' read -r bundle source name _; do
    if ! grep -qx "$bundle" <<<"$installed"; then
      echo "  MISSING  $name ($source) — $bundle"
      missing=$((missing + 1))
    fi
  done < <(declared)
  [[ $missing -eq 0 ]] && echo "  なし"

  echo "━━━ 端末に在るが宣言に無い ━━━"
  local declared_ids
  declared_ids=$(declared | cut -f1 | sort)
  while read -r bundle; do
    [[ -z $bundle ]] && continue
    if ! grep -qx "$bundle" <<<"$declared_ids"; then
      echo "  EXTRA    $bundle"
      extra=$((extra + 1))
    fi
  done <<<"$installed"
  [[ $extra -eq 0 ]] && echo "  なし"

  # Android 側と同じ判断: 宣言を満たしていないことだけを失敗にする。
  if [[ $missing -gt 0 ]]; then
    echo "宣言 ${missing} 件が未インストール。App Store / SideStore から手で入れる" >&2
    return 1
  fi
}

cmd_verify() {
  # App Store に在るかは公開 API で引ける。目録の綴り間違いはこれで落ちる。
  # sideload 行は自ビルドなので照会先が無く、対象外。
  local unknown=0
  while IFS=$'\t' read -r bundle source name _; do
    [[ $source == "appstore" ]] || continue
    local count
    count=$(curl -fsS "https://itunes.apple.com/lookup?bundleId=${bundle}&country=jp" |
      python3 -c 'import json,sys; print(json.load(sys.stdin)["resultCount"])')
    if [[ $count -eq 0 ]]; then
      echo "  UNKNOWN  $name — App Store に $bundle が無い"
      unknown=$((unknown + 1))
    fi
  done < <(declared)
  if [[ $unknown -gt 0 ]]; then
    echo "${unknown} 件の bundleId が解決できない" >&2
    return 1
  fi
  echo "appstore 行の bundleId はすべて実在する"
}

case "${1:-status}" in
  status) cmd_status ;;
  verify) cmd_verify ;;
  *)
    echo "usage: ./apps.sh [status|verify]" >&2
    exit 2
    ;;
esac
