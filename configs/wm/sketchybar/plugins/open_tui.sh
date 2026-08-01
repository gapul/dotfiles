#!/bin/bash

# sketchybar のアイコンから TUI を Ghostty の新規ウィンドウで開く。
#
# 以前は `open -na Ghostty.app --args -e <cmd>` を使っていたが、Ghostty 1.2+ は
# LaunchServices (open) 経由で渡された `-e` コマンドの実行前に
# 「Allow Ghostty to execute …?」というセキュリティ確認ダイアログを必ず出す。
# Quick Terminal 用の常駐インスタンスがあるため毎回このダイアログが挟まっていた。
#
# コマンドを CLI の `-e` ではなく設定ファイルの `command =` で渡すと、信頼された
# 設定由来とみなされ確認ダイアログは出ない。`-e` が暗黙で有効化していた
# quit-after-last-window-closed=true をここで明示し、TUI 終了時にこの専用
# インスタンスも自動終了させる (ゾンビ化防止)。

NIX_BIN="$HOME/.local/state/nix/profile/bin"

case "$1" in
calendar)
  TITLE="Calendar"
  COMMAND="$NIX_BIN/calcurse"
  ;;
music)
  TITLE="Music"
  COMMAND="$NIX_BIN/rmpc"
  ;;
system)
  TITLE="System Monitor"
  COMMAND="$NIX_BIN/btm"
  ;;
*)
  exit 1
  ;;
esac

[ -x "$COMMAND" ] || exit 1

# TUI ごとの一時設定ファイルを生成し、それを追加読み込みして起動する。
# --config-file は既定の config に加えて読まれるため、テーマ等はそのまま継承される。
CONF_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/sketchybar-tui"
mkdir -p "$CONF_DIR"
CONF="$CONF_DIR/$1.conf"
cat >"$CONF" <<EOF
title = $TITLE
command = $COMMAND
initial-window = true
quit-after-last-window-closed = true
EOF

open -na Ghostty.app --args --config-file="$CONF"
