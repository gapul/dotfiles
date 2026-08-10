#!/bin/sh
# ペインのスクロールバックを丸ごとエディタで開く (tmux.conf の prefix+e にバインド)。
# zellij の EditScrollback 相当。
#
# 引数の引用が tmux.conf にインラインで書くと成立しない (一時ファイル名を
# new-window のコマンド文字列へ埋め込む必要があるため) のでスクリプトにしてある。
#
# 母艦では nix/modules/home/terminal.nix がこのファイルを
# ~/.config/tmux/scrollback-edit.sh に配置する。nssh 先では ~/.config/tmux 自体が
# dotfiles への symlink なので、置いてあるだけで届く。
# つまりこのファイルが唯一の実体で、母艦とリモートで内容が分岐しない。
#
# $1: 取り込むペインの id (tmux が #{pane_id} を渡す)
set -eu

# mktemp: BSD (macOS) の `-t PREFIX` は GNU coreutils では
# 「X の数が少なすぎます」で失敗する。両方で通る明示テンプレートを使う。
f=$(mktemp "${TMPDIR:-/tmp}/tmux-scrollback.XXXXXX")

tmux capture-pane -p -S - -t "$1" >"$f"
tmux new-window -n scrollback "${EDITOR:-nvim} '$f'; rm -f '$f'"
