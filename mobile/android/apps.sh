#!/usr/bin/env bash
# apps.tsv に宣言したアプリと実機を突き合わせる。windows/winget/status.ps1 と同じ役割。
#
#   ./apps.sh status      # 宣言 vs 実機の差分。MISSING があれば exit 1 (既定)
#   ./apps.sh install     # 足りないものを fdroidcl 経由で adb install
#   ./apps.sh verify      # 宣言した packageId がリポジトリに実在するか
#   ./apps.sh obtainium   # 端末の Obtainium に貼る URL リストを出す
#
# 入れる仕事は fdroidcl (github.com/mvdan/fdroidcl) に任せている。F-Droid の
# インデックスを引いて APK を取り adb install するところまでやってくれるので、
# ここが持つのは「何を入れるか」の宣言と差分の判定だけ。
set -euo pipefail

cd "$(dirname "$0")"

# 宣言に無いリポジトリを見に行かせないため、fdroidcl の設定は母艦の ~/.config
# ではなくこのスクリプト専用の場所に置く。母艦で fdroidcl を手で使っていても
# 干渉しないし、この repo だけがリポジトリ構成の SSOT になる。
export XDG_CONFIG_HOME="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles-mobile/fdroidcl"
mkdir -p "$XDG_CONFIG_HOME"

# F-Droid 公式は fdroidcl の既定で入っている。追加で見るリポジトリだけ宣言する。
EXTRA_REPOS=(
  "izzy https://apt.izzysoft.de/fdroid/repo"
)

need() {
  command -v "$1" >/dev/null && return 0
  echo "$1 が無い: nix shell nixpkgs#$2 で入れて再実行 (just android-apps なら自動)" >&2
  exit 1
}

# packageId と repo の 2 列。コメントと空行を落とす。
declared() { grep -vE '^[[:space:]]*(#|$)' apps.tsv; }

# fdroidcl で入れられるもの (= play 以外) の packageId
installable() { declared | awk -F'\t' '$2 != "play" {print $1}'; }

ensure_repos() {
  for entry in "${EXTRA_REPOS[@]}"; do
    read -r name url <<<"$entry"
    # すでに在れば repo add はエラーになる。宣言済みという意味なので黙って流す。
    fdroidcl repo add "$name" "$url" >/dev/null 2>&1 || true
  done
}

installed_on_device() {
  need adb android-tools
  adb shell pm list packages -3 --user 0 </dev/null | tr -d '\r' | sed 's/^package://' | sort
}

cmd_status() {
  local installed missing=0 extra=0
  installed=$(installed_on_device)
  echo "━━━ 宣言したが端末に無い ━━━"
  while IFS=$'\t' read -r pkg repo; do
    if ! grep -qx "$pkg" <<<"$installed"; then
      echo "  MISSING  $pkg ($repo)"
      missing=$((missing + 1))
    fi
  done < <(declared)
  [[ $missing -eq 0 ]] && echo "  なし"

  echo "━━━ 端末に在るが宣言に無い ━━━"
  local declared_ids
  declared_ids=$(declared | cut -f1 | sort)
  while read -r pkg; do
    if ! grep -qx "$pkg" <<<"$declared_ids"; then
      echo "  EXTRA    $pkg"
      extra=$((extra + 1))
    fi
  done <<<"$installed"
  [[ $extra -eq 0 ]] && echo "  なし"

  # EXTRA では落とさない。端末で試しに入れたものが必ず在るし、消すかどうかは
  # 人が決めること。宣言を満たしていないこと (MISSING) だけを失敗として扱う。
  if [[ $missing -gt 0 ]]; then
    echo "宣言 ${missing} 件が未インストール。./apps.sh install で入れる" >&2
    return 1
  fi
}

cmd_install() {
  need fdroidcl fdroidcl
  local installed targets=()
  installed=$(installed_on_device)
  ensure_repos
  fdroidcl update

  while read -r pkg; do
    grep -qx "$pkg" <<<"$installed" || targets+=("$pkg")
  done < <(installable)

  if [[ ${#targets[@]} -gt 0 ]]; then
    fdroidcl install "${targets[@]}"
  else
    echo "fdroidcl で入れるものは無い"
  fi

  # Play にしか無いものは報告だけ。API が無いので自動化しようがない。
  while IFS=$'\t' read -r pkg repo; do
    [[ $repo == "play" ]] || continue
    grep -qx "$pkg" <<<"$installed" || echo "手で入れる (Play): $pkg"
  done < <(declared)
}

cmd_verify() {
  need fdroidcl fdroidcl
  ensure_repos
  fdroidcl update
  local unknown=0
  while read -r pkg; do
    if ! fdroidcl show "$pkg" >/dev/null 2>&1; then
      echo "  UNKNOWN  $pkg — リポジトリに無い (packageId の綴りか repo 列が違う)"
      unknown=$((unknown + 1))
    fi
  done < <(installable)
  if [[ $unknown -gt 0 ]]; then
    echo "${unknown} 件の packageId が解決できない" >&2
    return 1
  fi
  echo "宣言した packageId はすべてリポジトリに在る"
}

cmd_obtainium() {
  # 端末側の自動更新は Obtainium に任せる。URL は packageId から機械的に決まるので
  # ここで導出する (apps.tsv とは別に URL 一覧を持つと二重管理になる)。
  while IFS=$'\t' read -r pkg repo; do
    case "$repo" in
      fdroid) echo "https://f-droid.org/packages/$pkg" ;;
      izzy) echo "https://apt.izzysoft.de/fdroid/index/apk/$pkg" ;;
      play) echo "Play のため Obtainium では追えない: $pkg" >&2 ;;
    esac
  done < <(declared)
}

case "${1:-status}" in
  status) cmd_status ;;
  install) cmd_install ;;
  verify) cmd_verify ;;
  obtainium) cmd_obtainium ;;
  *)
    echo "usage: ./apps.sh [status|install|verify|obtainium]" >&2
    exit 2
    ;;
esac
