#!/usr/bin/env bash
# from-downloads フォルダを「内容ごと」に整理する。
#   - 親が内容カテゴリ(scholarship/papers/...) → from-downloads を解消し中身を親へ
#   - 親が一般名(~/Documents, ~/Pictures) → folder を意味ある名前にリネーム
#   - 同名衝突は " (N)" を付けて回避(上書きしない)
#   - iCloud データレスのまま安全(mv はメタデータ操作)
#
# 使い方: bash dissolve-from-downloads.sh        # ドライラン
#         bash dissolve-from-downloads.sh --apply # 実行
set -uo pipefail
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1

DOCS="$HOME/Documents"
PICS="$HOME/Pictures"
# 一般親 → リネーム先(英語)
RENAME_DOCS="$DOCS/coursework"
RENAME_PICS="$PICS/image-assets"

run() { if [ "$APPLY" = 1 ]; then "$@"; else echo "    DRY: $*"; fi; }

uniq_target() { # 衝突回避した移動先パスを返す
  local target="$1"
  [ ! -e "$target" ] && { printf '%s' "$target"; return; }
  local dir base ext n=2
  dir=$(dirname "$target"); base=$(basename "$target")
  if [ -d "$target" ]; then ext=""; else
    case "$base" in *.*) ext=".${base##*.}"; base="${base%.*}";; *) ext="";; esac
  fi
  while [ -e "$dir/$base ($n)$ext" ]; do n=$((n+1)); done
  printf '%s' "$dir/$base ($n)$ext"
}

dissolve() { # $1=from-downloads dir, $2=親
  local src="$1" dst="$2" moved=0 col=0
  shopt -s dotglob nullglob
  for item in "$src"/*; do
    local base target; base=$(basename "$item"); target="$dst/$base"
    if [ -e "$target" ]; then target=$(uniq_target "$target"); col=$((col+1)); fi
    run mv "$item" "$target"; moved=$((moved+1))
  done
  shopt -u dotglob nullglob
  run rmdir "$src"
  echo "  解消: $src → $dst  (移動 $moved, 衝突回避 $col)"
}

rename_folder() { # $1=from-downloads dir, $2=リネーム先
  local src="$1" target="$2"
  if [ -e "$target" ]; then
    echo "  リネーム先 $target が既存 → そこへ解消(dissolve)"
    dissolve "$src" "$target"
  else
    run mv "$src" "$target"
    echo "  リネーム: $src → $target"
  fi
}

echo "===== from-downloads 整理 $([ "$APPLY" = 1 ] && echo '(実行)' || echo '(ドライラン)') ====="
while IFS= read -r d; do
  parent=$(dirname "$d")
  case "$parent" in
    "$DOCS") rename_folder "$d" "$RENAME_DOCS" ;;
    "$PICS") rename_folder "$d" "$RENAME_PICS" ;;
    *)       dissolve "$d" "$parent" ;;
  esac
done < <(find "$DOCS" "$PICS" -type d -name "from-downloads" 2>/dev/null | sort)

echo "===== 完了 ====="
echo "残 from-downloads:"; find "$DOCS" "$PICS" -type d -name "from-downloads" 2>/dev/null || echo "  (なし)"
