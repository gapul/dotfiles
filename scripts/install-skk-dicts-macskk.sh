#!/usr/bin/env bash
# macSKK の sandbox Container に SKK 公開辞書を入れる。
# 辞書そのものは nix が $XDG_DATA_HOME/skk に置く(modules/home/editor.nix、skkeleton と共用)。
# sandbox の都合で symlink 不可 → real file コピー(~9MB の二重持ち)。
# コピー先が他アプリの Container なので activation ではなくこの手動スクリプト:
# macSKK が動いている最中に「削除 → 配置」しないと検出されない(下記)。
#
# macSKK は NSFilePresenter で「新規 file appear」イベントでしか検出しないので、
# **macSKK が動作中**に「削除 → 配置」する必要がある(README 参照)。

set -euo pipefail

SRC="${XDG_DATA_HOME:-$HOME/.local/share}/skk"
DST="${HOME}/Library/Containers/net.mtgto.inputmethod.macSKK/Data/Documents/Dictionaries"
DICTS=(L geo jinmei propernoun station)

if [[ ! -d "$DST" ]]; then
  echo "ERROR: macSKK Container 不在。macSKK を 1 度起動してから再実行してください。" >&2
  echo "  $DST" >&2
  exit 1
fi

if ! pgrep -fq "/Library/Input Methods/macSKK.app/Contents/MacOS/macSKK"; then
  echo "WARN: macSKK プロセスが見つかりません。" >&2
  echo "  検出機構(NSFilePresenter)が動かないので、日本語入力で macSKK を起こしてから再実行してください。" >&2
  exit 1
fi

for d in "${DICTS[@]}"; do
  file="SKK-JISYO.$d"
  if [[ ! -f "$SRC/$file" ]]; then
    echo "skip $file (ソース不在: $SRC/$file — 辞書は nix が置くので先に just rebuild)"
    continue
  fi
  # 削除 → ditto = macSKK の NSFilePresenter が「新規 appear」として検出
  rm -f "$DST/$file"
  sleep 0.5
  ditto "$SRC/$file" "$DST/$file"
  sleep 0.8
  echo "✓ $file"
done

echo ""
echo "完了。macSKK 設定画面 → Dictionaries タブを開いて、"
echo "各辞書のトグルを ON にしてください(初回のみ)。"
