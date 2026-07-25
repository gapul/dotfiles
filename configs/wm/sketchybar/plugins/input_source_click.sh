#!/bin/bash

SOURCES="$(defaults read com.apple.HIToolbox AppleSelectedInputSources 2>/dev/null)"

if printf '%s\n' "$SOURCES" | grep -q 'net\.mtgto\.inputmethod\.macSKK'; then
  if [ "$BUTTON" = "right" ]; then
    TARGET="private"
  else
    TARGET="settings"
  fi

  RESTORE_INPUT_MENU=0
  MENU_BAR_COUNT="$(osascript -e 'tell application "System Events" to tell process "TextInputMenuAgent" to get count of menu bars' 2>/dev/null)"
  if [ "${MENU_BAR_COUNT:-0}" -lt 2 ]; then
    INPUT_MENU_WAS_VISIBLE="$(defaults read com.apple.TextInputMenu visible 2>/dev/null || echo 0)"
    defaults write com.apple.TextInputMenu visible -bool true
    killall TextInputMenuAgent 2>/dev/null || true

    for _ in 1 2 3 4 5 6 7 8 9 10; do
      MENU_BAR_COUNT="$(osascript -e 'tell application "System Events" to tell process "TextInputMenuAgent" to get count of menu bars' 2>/dev/null)"
      [ "${MENU_BAR_COUNT:-0}" -ge 2 ] && break
      sleep 0.2
    done

    [ "$INPUT_MENU_WAS_VISIBLE" = "1" ] || RESTORE_INPUT_MENU=1
  fi

  osascript - "$TARGET" <<'APPLESCRIPT'
on run argv
set targetAction to item 1 of argv
tell application "System Events"
  tell process "TextInputMenuAgent"
    set inputMenuItem to menu bar item 1 of menu bar 2
    click inputMenuItem
    delay 0.5
    set inputMenu to menu 1 of inputMenuItem

    if targetAction is "settings" then
      if exists menu item "Preferences…" of inputMenu then
        click menu item "Preferences…" of inputMenu
        return
      else if exists menu item "環境設定…" of inputMenu then
        click menu item "環境設定…" of inputMenu
        return
      end if
    else if targetAction is "private" then
      if exists menu item "Private mode" of inputMenu then
        click menu item "Private mode" of inputMenu
        return
      else if exists menu item "プライベートモード" of inputMenu then
        click menu item "プライベートモード" of inputMenu
        return
      end if
    end if

    key code 53
  end tell
end tell
end run
APPLESCRIPT

  if [ "$RESTORE_INPUT_MENU" = "1" ]; then
    sleep 0.5
    defaults write com.apple.TextInputMenu visible -bool false
    killall TextInputMenuAgent 2>/dev/null || true
  fi
else
  if [ "$BUTTON" != "right" ]; then
    open 'x-apple.systempreferences:com.apple.Keyboard-Settings.extension?InputSources'
  fi
fi
