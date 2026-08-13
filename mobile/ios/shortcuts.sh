#!/usr/bin/env bash
# ショートカットを repo に取り込み、repo から端末へ戻す。
#
#   ./shortcuts.sh export   # 母艦の Shortcuts から shortcuts/*.plist に書き出す
#   ./shortcuts.sh status   # 書き出し済みの宣言と母艦の一覧の差分
#   ./shortcuts.sh build    # shortcuts/*.cherri を署名済み .shortcut にする
#
# ショートカットは iCloud で iPhone と母艦を往復しているので、母艦の
# ~/Library/Shortcuts/Shortcuts.sqlite を見れば端末を繋がずに中身が読める。
# 中身は素の bplist で暗号化されていない。
#
# 新規に書くときは Cherri (github.com/electrikmilk/cherri) を使う。手で組んだ
# plist は `shortcuts sign` に弾かれる (形式が合っていても通らない) が、Cherri は
# 署名済みの .shortcut (AEA1 コンテナ) をそのまま吐く。
set -euo pipefail

cd "$(dirname "$0")"
db="$HOME/Library/Shortcuts/Shortcuts.sqlite"
dir="shortcuts"
# 手で叩く道具なので nix run で足りる。ref を固定して、走らせるたびに
# 上流の最新が降ってくることは避ける。
cherri_ref="github:electrikmilk/cherri/v2.3.0"

cmd_export() {
  [[ -f $db ]] || {
    echo "Shortcuts の DB が無い: $db" >&2
    exit 1
  }
  mkdir -p "$dir"

  # ZACTIONS は行 id で、実体は ZSHORTCUTACTIONS.ZDATA の bplist。
  # 名前にスラッシュや空白が入るのでファイル名は sed で均す。
  local count=0
  while IFS=$'\t' read -r name pk; do
    [[ -z $name ]] && continue
    local safe="${name// /-}"
    safe="${safe//\//-}"
    # BLOB は hex で受けて戻す。sqlite3 の writefile は出力先がファイルでないと
    # 使えず、素の SELECT だとバイナリが端末経由で壊れる。
    sqlite3 "$db" "SELECT hex(a.ZDATA) FROM ZSHORTCUTACTIONS a WHERE a.ZSHORTCUT=$pk;" |
      xxd -r -p >"$dir/.tmp.bplist" 2>/dev/null || true
    # bplist のままでは差分が読めないので XML に開く。
    if plutil -convert xml1 -o "$dir/${safe}.plist" "$dir/.tmp.bplist" 2>/dev/null; then
      echo "  書き出し: ${safe}.plist"
      count=$((count + 1))
    else
      echo "  失敗: $name (中身を読めなかった)" >&2
    fi
  done < <(sqlite3 -separator $'\t' "$db" \
    "SELECT ZNAME, Z_PK FROM ZSHORTCUT WHERE ZTOMBSTONED IS NULL OR ZTOMBSTONED=0;")
  rm -f "$dir/.tmp.bplist"
  echo "${count} 件を書き出した"
}

cmd_status() {
  [[ -f $db ]] || {
    echo "Shortcuts の DB が無い: $db" >&2
    exit 1
  }
  local live declared missing=0 extra=0
  live=$(sqlite3 "$db" "SELECT ZNAME FROM ZSHORTCUT WHERE ZTOMBSTONED IS NULL OR ZTOMBSTONED=0;" | sed 's/ /-/g; s|/|-|g' | sort)
  declared=$(find "$dir" -name '*.plist' -exec basename {} .plist \; 2>/dev/null | sort)

  echo "━━━ repo に在るが母艦に無い ━━━"
  while read -r n; do
    [[ -z $n ]] && continue
    grep -qx "$n" <<<"$live" || {
      echo "  MISSING  $n"
      missing=$((missing + 1))
    }
  done <<<"$declared"
  [[ $missing -eq 0 ]] && echo "  なし"

  echo "━━━ 母艦に在るが repo に無い ━━━"
  while read -r n; do
    [[ -z $n ]] && continue
    grep -qx "$n" <<<"$declared" || {
      echo "  EXTRA    $n"
      extra=$((extra + 1))
    }
  done <<<"$live"
  [[ $extra -eq 0 ]] && echo "  なし"

  # アプリ側と同じ判断。EXTRA は ./shortcuts.sh export で取り込めるので落とさない。
  [[ $missing -gt 0 ]] && {
    echo "repo にしか無いものが ${missing} 件" >&2
    return 1
  }
  return 0
}

cmd_build() {
  shopt -s nullglob
  local sources=("$dir"/*.cherri)
  if [[ ${#sources[@]} -eq 0 ]]; then
    echo "$dir に .cherri が無い。新規に書くときだけ使う (既存の取り込みは export)" >&2
    return 0
  fi
  local out
  out=$(mktemp -d)
  for src in "${sources[@]}"; do
    (cd "$out" && nix run "$cherri_ref" -- "$OLDPWD/$src")
  done
  echo "署名済み .shortcut を $out に置いた"
  # 母艦の Shortcuts に入れれば iCloud が iPhone に運ぶ。open は確認ダイアログを出す。
  echo "取り込むには: open $out/*.shortcut"
}

case "${1:-status}" in
export) cmd_export ;;
status) cmd_status ;;
build) cmd_build ;;
*)
  echo "usage: ./shortcuts.sh [export|status|build]" >&2
  exit 2
  ;;
esac
