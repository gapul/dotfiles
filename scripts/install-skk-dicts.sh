#!/usr/bin/env bash
# SKK 公開辞書(SKK-JISYO.*) を ~/.skk/ に install する。
# skkeleton (nvim) が読み、macSKK は別途 Container に ditto コピーする
# (sandbox の都合で symlink 不可、README 参照)。
#
# idempotent: 既存ファイルは skip。--force で再 download。

set -euo pipefail

DEST="${HOME}/.skk"
BASE="https://skk-dev.github.io/dict"
DICTS=(L geo jinmei propernoun station)
FORCE="${1:-}"

mkdir -p "$DEST"

for d in "${DICTS[@]}"; do
  file="SKK-JISYO.$d"
  if [[ -f "$DEST/$file" && "$FORCE" != "--force" ]]; then
    echo "✓ $file (skip, 既存)"
    continue
  fi
  echo "↓ $file"
  curl -fsSL "$BASE/$file.gz" | gunzip > "$DEST/$file"
done

echo ""
echo "完了。skkeleton (nvim) は ~/.skk/ を直接読みます。"
echo ""
echo "macSKK 側に同じ辞書を入れたい場合は別途以下を実行:"
echo "  bash ~/dotfiles/scripts/install-skk-dicts-macskk.sh"
