#!/usr/bin/env bash
# メインディスプレイの論理縦解像度から Ghostty の font-size を算出し、
# ~/.config/ghostty.local/font-size.conf に書き出す。
# Ghostty の config が末尾で `config-file = ?~/.config/ghostty.local/font-size.conf`
# を読み込み (後勝ち) するため、ここで書いた font-size が最終的に採用される。
#
# 基準は sketchybar と揃える: 縦 REF_H pt のとき BASE、縦解像度比で比例スケール。
# nh home switch の home.activation から呼ばれる。解像度を変えたら再度 switch するか、
# このスクリプトを手で実行 → Ghostty で config reload (デフォルト cmd+shift+,) すれば反映。
#
# macOS 以外 (swift/CoreGraphics 不在) では CUR_H が取れず BASE にフォールバックする。
set -eu

REF_H=1112
BASE=13
OUT_DIR="$HOME/.config/ghostty.local"
OUT="$OUT_DIR/font-size.conf"

# メインディスプレイの論理縦(ポイント)を CoreGraphics で取得 (最も確実)
CUR_H=$(/usr/bin/swift - <<'SWIFT' 2>/dev/null || true
import CoreGraphics
print(Int(CGDisplayBounds(CGMainDisplayID()).height))
SWIFT
)
case "${CUR_H:-}" in ''|*[!0-9]*) CUR_H=$REF_H ;; esac
[ "$CUR_H" -gt 0 ] 2>/dev/null || CUR_H=$REF_H

FS=$(/usr/bin/awk -v h="$CUR_H" -v r="$REF_H" -v b="$BASE" 'BEGIN{printf "%.0f", b*h/r}')

/bin/mkdir -p "$OUT_DIR"
printf '# 自動生成 (scripts/ghostty-fontsize.sh)。手で編集しても switch/再実行で上書きされる。\nfont-size = %s\n' "$FS" > "$OUT"
echo "ghostty font-size = $FS (CUR_H=$CUR_H, REF_H=$REF_H, BASE=$BASE)"
