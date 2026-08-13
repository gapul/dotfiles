#!/usr/bin/env bash
# apps.tsv に宣言したアプリと実機を突き合わせる。windows/winget/status.ps1 と同じ役割。
#
#   ./apps.sh status      # 宣言 vs 実機の差分。MISSING があれば exit 1 (既定)
#   ./apps.sh install     # F-Droid / IzzyOnDroid のものを fdroidcl 経由で adb install
#   ./apps.sh verify      # 宣言した packageId が配布元に実在するか (4 経路すべて)
#   ./apps.sh obtainium   # 端末の Obtainium に貼る URL リストを出す
#   ./apps.sh adopt       # 端末に在って宣言に無いものを、経路を判定して tsv 行で出す
#
# 母艦から入れられるのは F-Droid 系だけ。GitHub 配布は端末の Obtainium が、
# Play は Aurora Store が担う。ここが持つのは「何を入れるか」の宣言と差分の判定で、
# 入れる仕事は経路ごとの道具に任せている。
set -euo pipefail

cd "$(dirname "$0")"

# 宣言に無いリポジトリを見に行かせないため、fdroidcl の設定は母艦の ~/.config
# ではなくこのスクリプト専用の場所に置く。母艦で fdroidcl を手で使っていても
# 干渉しないし、この repo だけがリポジトリ構成の SSOT になる。
#
# XDG_CONFIG_HOME はスクリプト全体に export しない。fdroidcl の設定を退けるつもりで
# gh の認証情報 ($XDG_CONFIG_HOME/gh/hosts.yml) まで見失わせ、verify の GitHub 照会が
# 黙って全部 UNKNOWN になる。差し替えるのは fdroidcl を呼ぶ瞬間だけにする。
FDROIDCL_CONFIG="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles-mobile/fdroidcl"
mkdir -p "$FDROIDCL_CONFIG"
fdroidcl() { XDG_CONFIG_HOME="$FDROIDCL_CONFIG" command fdroidcl "$@"; }

# F-Droid 公式は fdroidcl の既定で入っている。追加で見るリポジトリだけ宣言する。
EXTRA_REPOS=(
  "izzy https://apt.izzysoft.de/fdroid/repo"
)

need() {
  command -v "$1" >/dev/null && return 0
  echo "$1 が無い: nix shell nixpkgs#$2 で入れて再実行 (just android-apps なら自動)" >&2
  exit 1
}

# packageId / source / ref の 3 列。コメントと空行を落とす。
declared() { grep -vE '^[[:space:]]*(#|$)' apps.tsv; }

# fdroidcl で入れられるもの (= F-Droid 系) の packageId
fdroid_ids() { declared | awk -F'\t' '$2 == "fdroid" || $2 == "izzy" {print $1}'; }

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
  while IFS=$'\t' read -r pkg source _; do
    if ! grep -qx "$pkg" <<<"$installed"; then
      echo "  MISSING  $pkg ($source)"
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
    echo "宣言 ${missing} 件が未インストール。./apps.sh install で入る分を入れる" >&2
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
  done < <(fdroid_ids)

  if [[ ${#targets[@]} -gt 0 ]]; then
    fdroidcl install "${targets[@]}"
  else
    echo "fdroidcl で入れるものは無い"
  fi

  # 残りは端末側の道具の仕事。母艦から入れる手段が無いので報告だけする。
  while IFS=$'\t' read -r pkg source _; do
    grep -qx "$pkg" <<<"$installed" && continue
    case "$source" in
    github) echo "端末の Obtainium で入れる: $pkg" ;;
    play) echo "端末の Aurora Store で入れる: $pkg" ;;
    esac
  done < <(declared)
}

cmd_verify() {
  local unknown=0 repos_updated=false
  while IFS=$'\t' read -r pkg source ref; do
    local ok=true
    case "$source" in
    fdroid | izzy)
      need fdroidcl fdroidcl
      # 索引の取得は 1 回だけ。行ごとに update すると毎回 13MB 引きに行く。
      if ! $repos_updated; then
        ensure_repos
        fdroidcl update
        repos_updated=true
      fi
      fdroidcl show "$pkg" >/dev/null 2>&1 || ok=false
      ;;
    github)
      # リリースに APK が付いていなければ Obtainium が追えない。存在だけでなく
      # 「取れる形で配られているか」まで見る。
      #
      # gh があればそちらを使う。未認証の GitHub API は 60 回/時で、宣言が
      # 増えると verify が rate limit で落ちる (認証済みなら 5000 回/時)。
      # curl 側に -L が要るのは、repo が改名されると API が 301 を返すため
      # (実際 Catfriend1/syncthing-android は researchxxl/ に移っていた)。
      #
      # 一度変数に受けてから grep する。パイプで grep -q に渡すと、最初の一致で
      # grep が閉じた先を書き続けた gh / curl が SIGPIPE で死に、pipefail が
      # それを失敗として拾って全部 UNKNOWN になる。
      local assets
      if command -v gh >/dev/null; then
        assets=$(gh api "repos/${ref}/releases/latest" --jq '[.assets[].name]' 2>/dev/null || true)
      else
        assets=$(curl -fsSL "https://api.github.com/repos/${ref}/releases/latest" || true)
      fi
      [[ $assets == *.apk* ]] || ok=false
      ;;
    play)
      curl -fsS -o /dev/null "https://play.google.com/store/apps/details?id=${pkg}&gl=us" || ok=false
      ;;
    *)
      echo "  BAD      $pkg — source 列が不正: $source"
      unknown=$((unknown + 1))
      continue
      ;;
    esac
    if ! $ok; then
      echo "  UNKNOWN  $pkg — $source に見つからない (packageId か ref が違う)"
      unknown=$((unknown + 1))
    fi
  done < <(declared)

  if [[ $unknown -gt 0 ]]; then
    echo "${unknown} 件が配布元に解決できない" >&2
    return 1
  fi
  echo "宣言したアプリはすべて配布元に在る"
}

cmd_obtainium() {
  # 端末側の自動更新は Obtainium に任せる。URL は packageId / ref から機械的に
  # 決まるので、ここで導出する (URL 一覧を別に持つと二重管理になる)。
  while IFS=$'\t' read -r pkg source ref; do
    case "$source" in
    fdroid) echo "https://f-droid.org/packages/$pkg" ;;
    izzy) echo "https://apt.izzysoft.de/fdroid/index/apk/$pkg" ;;
    github) echo "https://github.com/$ref" ;;
    play) echo "Aurora Store の担当なので Obtainium では追えない: $pkg" >&2 ;;
    esac
  done < <(declared)
}

# 端末に在って宣言に無いものを apps.tsv の行として出す。Aurora Store で入れたものを
# 手で書き写すのは packageId を目で追う作業になるので、経路の判定ごと機械にやらせる。
#
#   ./apps.sh adopt >>apps.tsv   # 追記してから中身を見て整える
cmd_adopt() {
  local installed declared_ids extra
  installed=$(installed_on_device)
  declared_ids=$(declared | cut -f1 | sort)
  extra=$(comm -13 <(printf '%s\n' "$declared_ids") <(printf '%s\n' "$installed"))

  if [[ -z $extra ]]; then
    echo "# 宣言に無いアプリは端末に無い" >&2
    return 0
  fi

  ensure_repos
  fdroidcl update >&2 || true

  while read -r pkg; do
    [[ -z $pkg ]] && continue
    # F-Droid 系に在ればそちらが一次。無ければ Play を見る。どちらでも引けなければ
    # play にしておく (Aurora Store で入れた覚えのあるもの) が、判定できていない
    # ことは行末に残す。GitHub 配布があるなら github に寄せた方が Obtainium が追える。
    if fdroidcl show "$pkg" >/dev/null 2>&1; then
      printf '%s\tfdroid\t-\n' "$pkg"
    elif curl -fsS -o /dev/null "https://play.google.com/store/apps/details?id=${pkg}&gl=us"; then
      printf '%s\tplay\t-\n' "$pkg"
    else
      printf '%s\tplay\t-\t# 配布元を特定できず\n' "$pkg"
    fi
  done <<<"$extra"
}

# play 行を Aurora Store の Favourites に import できる JSON にする。
# Aurora 4.6 以降は Favourites の import/export と一括インストールを持っているので、
# Play しか配布元が無いものも「ファイルを渡して端末側で入れる」に寄せられる。
# 形式は AuroraStore の data/room/favourite/{ImportExport,Favourite}.kt に合わせた。
#
#   ./apps.sh aurora >aurora-favourites.json
#   adb push aurora-favourites.json /sdcard/Download/
#   端末で Aurora Store → Favourites → Import → 一括インストール
cmd_aurora() {
  # displayName は packageId をそのまま置く。表示用のラベルでしかなく、
  # 正しい名前を取るには Play を 1 件ずつ引く必要があって割に合わない。
  # added は 0 固定 (実行のたびに変えるとファイルが毎回差分になる)。
  declared | awk -F'\t' '$2 == "play" { print $1 }' | python3 -c '
import json, sys
favourites = [
    {
        "packageName": pkg,
        "displayName": pkg,
        "iconURL": "",
        "added": 0,
        "mode": "IMPORT",
    }
    for pkg in sys.stdin.read().split()
]
print(json.dumps({"favourites": favourites}, indent=2))
'
}

case "${1:-status}" in
status) cmd_status ;;
install) cmd_install ;;
verify) cmd_verify ;;
obtainium) cmd_obtainium ;;
adopt) cmd_adopt ;;
aurora) cmd_aurora ;;
*)
  echo "usage: ./apps.sh [status|install|verify|obtainium|adopt|aurora]" >&2
  exit 2
  ;;
esac
