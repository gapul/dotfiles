#!/bin/bash

# 蓋を閉じてもスリープしない設定 (pmset -a disablesleep 1) の表示とトグル。
# 判定は zsh の nosleep 関数 (nix/home/darwin.nix) と同じ pmset -g の SleepDisabled を見る。

source "$HOME/.config/sketchybar-colors.sh"

disabled() { pmset -g | grep -q "SleepDisabled.*1"; }

if [ "$1" = "toggle" ]; then
  disabled && next=0 || next=1
  # この 2 コマンドだけ sudoers で NOPASSWD にしてあるので無認証で切り替わる (nix/hosts/darwin-common.nix)。
  # ルールが無いホストでは、sketchybar からパスワードを聞けないので GUI の認証ダイアログに落とす。
  sudo -n /usr/bin/pmset -a disablesleep "$next" 2>/dev/null ||
    osascript -e "do shell script \"pmset -a disablesleep $next\" with administrator privileges" >/dev/null 2>&1
fi

if disabled; then
  sketchybar --set "$NAME" icon.color=$YELLOW
else
  sketchybar --set "$NAME" icon.color=$GREY
fi
