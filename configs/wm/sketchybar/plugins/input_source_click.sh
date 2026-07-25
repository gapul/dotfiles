#!/bin/bash

SOURCES="$(defaults read com.apple.HIToolbox AppleSelectedInputSources 2>/dev/null)"

if printf '%s\n' "$SOURCES" | grep -q 'net\.mtgto\.inputmethod\.macSKK'; then
  osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "TextInputMenuAgent"
    set inputMenuItem to menu bar item 1 of menu bar 2
    click inputMenuItem
    delay 0.2

    repeat with itemRef in menu items of menu 1 of inputMenuItem
      set itemTitle to ""
      try
        set itemTitle to title of itemRef as text
      end try
      if itemTitle contains "Preferences" or itemTitle contains "環境設定" then
        click itemRef
        return
      end if
    end repeat

    key code 53
  end tell
end tell
APPLESCRIPT
else
  open 'x-apple.systempreferences:com.apple.Keyboard-Settings.extension?InputSources'
fi
