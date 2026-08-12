#!/bin/sh
#
# 走っている sketchybar 全インスタンスへ同じコマンドを投げる。
#
# バーは 2 本ある (内蔵用 = sketchybar / 外部モニタ用 = sketchybar-ext)。
# どちらに届くかは呼び出したバイナリの名前で決まるので、常駐エージェント側から
# reload や trigger を打つときは両方に投げないと片方だけ表示が止まる。
# インスタンス内の plugins は PATH shim があるので、こちらを使う必要はない。
#
#   例: sb-all.sh --reload
#       sb-all.sh --trigger omniwm_workspace_change FOO=bar
#
# 応答が無いインスタンス (未起動) はエラーを吐くだけで害はないので握りつぶす。

SB_MAIN=/opt/homebrew/bin/sketchybar
SB_EXT="$HOME/.config/sketchybar/bin-ext/sketchybar-ext"

[ -x "$SB_MAIN" ] && "$SB_MAIN" "$@" >/dev/null 2>&1
[ -x "$SB_EXT" ] && "$SB_EXT" "$@" >/dev/null 2>&1

exit 0
