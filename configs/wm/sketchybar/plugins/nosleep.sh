#!/bin/bash

# 蓋を閉じてもスリープしない設定 (pmset -a disablesleep 1) の状態表示。
# 判定は zsh の nosleep 関数 (nix/home/darwin.nix) と同じ pmset -g の SleepDisabled を見る。
# 通常スリープのときはアイテムごと消す = 出ていること自体が「戻し忘れ」の警告になる。

source "$HOME/.config/sketchybar-colors.sh"

if [ "$1" = "off" ]; then
  # sketchybar からは sudo のパスワードを聞けないので、GUI の認証ダイアログ (Touch ID 可) 経由で解除する。
  osascript -e 'do shell script "pmset -a disablesleep 0" with administrator privileges' >/dev/null 2>&1
fi

if pmset -g | grep -q "SleepDisabled.*1"; then
  sketchybar --set "$NAME" drawing=on icon.color=$YELLOW
else
  sketchybar --set "$NAME" drawing=off
fi
