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
    echo "宣言 ${missing} 件が未インストール。App Store / AltStore から手で入れる" >&2
    return 1
  fi
}

# sources.tsv の該当 kind の source を全部引いて、bundleIdentifier を一覧にする。
# source は AltStore の JSON 形式なので、ここを見れば「宣言した bundleId が
# 本当にその経路から入るものか」を機械で確かめられる。
source_bundles() {
  local kind=$1
  while IFS=$'\t' read -r _ src_kind url; do
    [[ -z ${src_kind:-} || $_ == \#* || $src_kind != "$kind" ]] && continue
    curl -fsSL "$url" |
      python3 -c 'import json,sys; [print(a.get("bundleIdentifier","")) for a in json.load(sys.stdin).get("apps",[])]'
  done < <(grep -vE '^[[:space:]]*(#|$)' sources.tsv)
}

cmd_verify() {
  local unknown=0 classic pal
  # source は行ごとに引かず 1 回だけ引く。宣言の数だけ HTTP を叩かない。
  classic=$(source_bundles classic)
  pal=$(source_bundles pal)

  while IFS=$'\t' read -r bundle source name _; do
    local ok=true
    case "$source" in
    appstore)
      [[ $(curl -fsS "https://itunes.apple.com/lookup?bundleId=${bundle}&country=jp" |
        python3 -c 'import json,sys; print(json.load(sys.stdin)["resultCount"])') -gt 0 ]] || ok=false
      ;;
    altstore-classic) grep -qx "$bundle" <<<"$classic" || ok=false ;;
    altstore-pal) grep -qx "$bundle" <<<"$pal" || ok=false ;;
    *)
      echo "  BAD      $name — source 列が不正: $source"
      unknown=$((unknown + 1))
      continue
      ;;
    esac
    if ! $ok; then
      echo "  UNKNOWN  $name — $source に $bundle が無い"
      unknown=$((unknown + 1))
    fi
  done < <(declared)

  if [[ $unknown -gt 0 ]]; then
    echo "${unknown} 件の bundleId が解決できない" >&2
    return 1
  fi
  echo "宣言したアプリはすべて経路上に実在する"
}

case "${1:-status}" in
status) cmd_status ;;
verify) cmd_verify ;;
*)
  echo "usage: ./apps.sh [status|verify]" >&2
  exit 2
  ;;
esac
