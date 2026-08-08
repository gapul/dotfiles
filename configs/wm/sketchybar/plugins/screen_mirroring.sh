#!/bin/bash

source "$HOME/.config/sketchybar-colors.sh"

if [ "$1" = "click" ]; then
  # Control Center パネルではなく、公式の「画面ミラーリング」メニューバー項目を
  # 直接開く (System Settings > Control Center > 画面ミラーリング = 常にメニューバーに表示)。
  # 項目は ControlCenter プロセスが所有し、AXIdentifier は
  # com.apple.menuextra.screen-mirroring で安定している。
  osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "ControlCenter"
    set targetItem to missing value
    repeat with candidate in menu bar items of menu bar 1
      try
        if (value of attribute "AXIdentifier" of candidate) as text is "com.apple.menuextra.screen-mirroring" then
          set targetItem to candidate
          exit repeat
        end if
      end try
    end repeat
    if targetItem is missing value then ¬
      error "Screen Mirroring menu bar item not found. Enable it in System Settings > Control Center > Screen Mirroring."
    click targetItem
  end tell
end tell
APPLESCRIPT
  exit 0
fi

if system_profiler SPDisplaysDataType 2>/dev/null | grep -q 'Mirror: On'; then
  sketchybar --set "$NAME" icon.color="$GREEN"
else
  sketchybar --set "$NAME" icon.color="$GREY"
fi
