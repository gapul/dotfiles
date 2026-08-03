#!/usr/bin/env bash
#
# WM 抽象化レイヤー (aerospace / omniwm)
#
# sketchybar の workspace ウィジェット群が必要とする照会だけを関数化し、
# 稼働中の WM を pgrep で自動判別して omniwmctl / aerospace CLI に振り分ける。
# aerospace は撤去済みだが、フォールバック分岐は互換のため残している。
#
# 前提:
#   - omniwm 側は IPC 有効 (settings.toml: ipcEnabled = true)
#   - ワークスペース名 = aerospace の workspace 名 = omniwm の rawName ("1".."9")
#   - モニター ID: aerospace は数値、omniwm は "display:N" → N に正規化

AEROSPACE=/opt/homebrew/bin/aerospace
OMNIWMCTL=/opt/homebrew/bin/omniwmctl
JQ="$HOME/.local/state/nix/profile/bin/jq"
[ -x "$JQ" ] || JQ="$HOME/.nix-profile/bin/jq"
[ -x "$JQ" ] || JQ=$(command -v jq)

# 呼び出し元でエクスポート済みならそれを優先 (1 イベント処理内での再判定を避ける)
if [ -z "$WM_BACKEND" ]; then
  if pgrep -xq OmniWM; then
    WM_BACKEND=omniwm
  else
    WM_BACKEND=aerospace
  fi
fi
export WM_BACKEND

_ow_workspaces() {
  "$OMNIWMCTL" query workspaces --format json 2>/dev/null
}

# フォーカス中の workspace 名
wm_focused_workspace() {
  if [ "$WM_BACKEND" = omniwm ]; then
    _ow_workspaces | "$JQ" -r '.result.payload.workspaces[] | select(.isFocused) | .rawName'
  else
    "$AEROSPACE" list-workspaces --focused
  fi
}

# モニター ID の一覧 (数値, 1 行 1 件)
wm_list_monitors() {
  if [ "$WM_BACKEND" = omniwm ]; then
    "$OMNIWMCTL" query displays --format json 2>/dev/null |
      "$JQ" -r '.result.payload.displays[].id | sub("^display:"; "")'
  else
    "$AEROSPACE" list-monitors | awk '{print $1}'
  fi
}

# フォーカス中のモニター ID (数値)
wm_focused_monitor() {
  if [ "$WM_BACKEND" = omniwm ]; then
    "$OMNIWMCTL" query focused-monitor --format json 2>/dev/null |
      "$JQ" -r '.result.payload.display.id | sub("^display:"; "")'
  else
    "$AEROSPACE" list-monitors --focused | awk '{print $1}'
  fi
}

# 指定モニターの workspace 名一覧。$2: all | empty | nonempty
wm_list_workspaces() {
  local monitor="$1" filter="${2:-all}"
  if [ "$WM_BACKEND" = omniwm ]; then
    local cond
    case "$filter" in
      empty) cond='.counts.total == 0' ;;
      nonempty) cond='.counts.total > 0' ;;
      *) cond='true' ;;
    esac
    _ow_workspaces | "$JQ" -r --arg d "display:$monitor" \
      ".result.payload.workspaces[] | select(.display.id == \$d) | select($cond) | .rawName"
  else
    case "$filter" in
      empty) "$AEROSPACE" list-workspaces --monitor "$monitor" --empty ;;
      nonempty) "$AEROSPACE" list-workspaces --monitor "$monitor" --empty no ;;
      *) "$AEROSPACE" list-workspaces --monitor "$monitor" ;;
    esac
  fi
}

# 全 workspace 名
wm_list_workspaces_all() {
  if [ "$WM_BACKEND" = omniwm ]; then
    _ow_workspaces | "$JQ" -r '.result.payload.workspaces[].rawName'
  else
    "$AEROSPACE" list-workspaces --all
  fi
}

# workspace 内のアプリ名一覧 (icon_map.sh に渡す表示名)
wm_workspace_apps() {
  local ws="$1"
  if [ "$WM_BACKEND" = omniwm ]; then
    "$OMNIWMCTL" query windows --workspace "$ws" --fields app --format json 2>/dev/null |
      "$JQ" -r '.result.payload.windows[].app.name'
  else
    "$AEROSPACE" list-windows --workspace "$ws" | awk -F'|' '{gsub(/^ *| *$/, "", $2); print $2}'
  fi
}

# workspace へフォーカス移動 (クリック用)
wm_focus_workspace() {
  local ws="$1"
  if [ "$WM_BACKEND" = omniwm ]; then
    "$OMNIWMCTL" workspace focus-name "$ws" >/dev/null 2>&1
  else
    "$AEROSPACE" workspace "$ws"
  fi
}
