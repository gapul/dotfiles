#!/bin/bash

# 蓋を閉じてもスリープしない設定 (pmset -a disablesleep 1) の表示とトグル。
# 判定は zsh の nosleep 関数 (nix/home/darwin.nix) と同じ pmset -g の SleepDisabled を見る。

source "$HOME/.config/sketchybar-colors.sh"

disabled() { pmset -g | grep -q "SleepDisabled.*1"; }

if [ "$1" = "toggle" ]; then
  disabled && next=0 || next=1
  # sketchybar からは sudo のパスワードを聞けないので、GUI の認証ダイアログ (Touch ID 可) 経由で切り替える。
  osascript -e "do shell script \"pmset -a disablesleep $next\" with administrator privileges" >/dev/null 2>&1
fi

if disabled; then
  sketchybar --set "$NAME" icon.color=$YELLOW
else
  sketchybar --set "$NAME" icon.color=$GREY
fi
