#!/usr/bin/env bash
#
# WM 照会レイヤー (omniwm)
#
# sketchybar の workspace ウィジェット群が必要とする照会だけを関数化する。
# 以前は aerospace との二本立てだったが、aerospace は撤去済みで
# /opt/homebrew/bin/aerospace はもう存在しない。フォールバックを残しておくと
# OmniWM が落ちている間に「存在しないバイナリを叩いて空を返す」経路に入り、
# バーが黙って無表示になるだけなので、分岐ごと落とした。
#
# 前提:
#   - omniwm 側は IPC 有効 (settings.toml: ipcEnabled = true)
#   - ワークスペース名 = omniwm の rawName ("1".."9")
#   - モニター ID: omniwm は "display:N" → N に正規化
#
# 注: イベント名 aerospace_workspace_change と AEROSPACE_* 環境変数、
#     /tmp/sketchybar-aero-display.map は名前だけ据え置き。発火側 (omniwm-event.sh) と
#     受け側で一貫していて、改名しても挙動は変わらず差分だけが広がるため。

OMNIWMCTL=/opt/homebrew/bin/omniwmctl
JQ="$HOME/.local/state/nix/profile/bin/jq"
[ -x "$JQ" ] || JQ="$HOME/.nix-profile/bin/jq"
[ -x "$JQ" ] || JQ=$(command -v jq)

_ow_workspaces() {
  "$OMNIWMCTL" query workspaces --format json 2>/dev/null
}

# フォーカス中の workspace 名
wm_focused_workspace() {
  # workspaces[].isFocused は「フォーカスされた窓」基準で、空ワークスペースに
  # 切り替えると前のワークスペースを報告し続ける (壁紙連動が空WSで死ぬ原因)。
  # active-workspace クエリは WM 自身の現在WS状態なので空WSでも正しい。
  "$OMNIWMCTL" query active-workspace --format json 2>/dev/null |
    "$JQ" -r '.result.payload.workspace.rawName // empty'
}

# モニター ID の一覧 (数値, 1 行 1 件)
wm_list_monitors() {
  "$OMNIWMCTL" query displays --format json 2>/dev/null |
    "$JQ" -r '.result.payload.displays[].id | sub("^display:"; "")'
}

# モニター ID の一覧を frame.x 昇順 (画面の左→右) で返す。display map 生成用。
wm_list_monitors_by_x() {
  "$OMNIWMCTL" query displays --fields id,frame --format json 2>/dev/null |
    "$JQ" -r '.result.payload.displays | sort_by(.frame.x) | .[].id | sub("^display:"; "")'
}

# フォーカス中のモニター ID (数値)
wm_focused_monitor() {
  "$OMNIWMCTL" query focused-monitor --format json 2>/dev/null |
    "$JQ" -r '.result.payload.display.id | sub("^display:"; "")'
}

# 指定モニターの workspace 名一覧。$2: all | empty | nonempty
wm_list_workspaces() {
  local monitor="$1" filter="${2:-all}"
  local cond
  case "$filter" in
    empty) cond='.counts.total == 0' ;;
    nonempty) cond='.counts.total > 0' ;;
    *) cond='true' ;;
  esac
  _ow_workspaces | "$JQ" -r --arg d "display:$monitor" \
    ".result.payload.workspaces[] | select(.display.id == \$d) | select($cond) | .rawName"
}

# 全 workspace 名
wm_list_workspaces_all() {
  _ow_workspaces | "$JQ" -r '.result.payload.workspaces[].rawName'
}

# workspace 内のアプリ名一覧 (icon_map.sh に渡す表示名)
wm_workspace_apps() {
  local ws="$1"
  "$OMNIWMCTL" query windows --workspace "$ws" --fields app --format json 2>/dev/null |
    "$JQ" -r '.result.payload.windows[].app.name'
}

# workspace へフォーカス移動 (クリック用)
wm_focus_workspace() {
  local ws="$1"
  "$OMNIWMCTL" workspace focus-name "$ws" >/dev/null 2>&1
}
