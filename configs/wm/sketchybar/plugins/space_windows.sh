#!/usr/bin/env bash

set -euo pipefail

source "$CONFIG_DIR/colors.sh"

# キャッシュ変数
declare -A workspace_cache

reload_workspace_icon() {
  local workspace=$1
  
  # キャッシュ確認（1秒間有効）
  local cache_key="ws_${workspace}"
  local current_time
  current_time=$(date +%s)
  if [[ -n "${workspace_cache[$cache_key]:-}" ]] && [[ $current_time -lt ${workspace_cache[$cache_key]} ]]; then
    return
  fi
  
  # 一度のコマンドで必要な情報を取得（タイムアウト対策）
  local apps_raw
  apps_raw=$(timeout 3 aerospace list-windows --workspace "$workspace" 2>/dev/null | awk -F'|' '{gsub(/^ *| *$/, "", $2); print $2}' || echo "")
  
  local icon_strip=" "
  if [[ -n "$apps_raw" ]]; then
    # バッチ処理でアイコンマッピング
    while IFS= read -r app; do
      [[ -n "$app" ]] && icon_strip+=" $("$CONFIG_DIR"/plugins/icon_map.sh "$app")"
    done <<< "$apps_raw"
  else
    icon_strip=" —"
  fi
  
  sketchybar --animate sin 10 --set space."$workspace" label="$icon_strip"
  
  # 1秒間キャッシュ
  workspace_cache[$cache_key]=$((current_time + 1))
}

if [[ "$SENDER" = "aerospace_workspace_change" ]]; then
  # 必要な情報を一度に取得（タイムアウト対策）
  AEROSPACE_FOCUSED_MONITOR=$(timeout 3 aerospace list-monitors --focused 2>/dev/null | awk '{print $1}' || echo "1")
  AEROSAPCE_WORKSPACE_FOCUSED_MONITOR=$(timeout 3 aerospace list-workspaces --monitor focused --empty no 2>/dev/null || echo "")
  AEROSPACE_EMPTY_WORKESPACE=$(timeout 3 aerospace list-workspaces --monitor focused --empty 2>/dev/null || echo "")
  
  # 並列処理でワークスペースアイコンを更新
  {
    reload_workspace_icon "$AEROSPACE_PREV_WORKSPACE" &
    reload_workspace_icon "$AEROSPACE_FOCUSED_WORKSPACE" &
    wait
  }
  
  # sketchybar更新（個別実行）
  sketchybar --set space."$AEROSPACE_FOCUSED_WORKSPACE" \
    icon.highlight=true \
    label.highlight=true \
    background.border_color="$GREY"
  
  sketchybar --set space."$AEROSPACE_PREV_WORKSPACE" \
    icon.highlight=false \
    label.highlight=false \
    background.border_color="$BACKGROUND_2"
  
  # 必要時のみワークスペース表示状態を更新
  if [[ -n "${AEROSAPCE_WORKSPACE_FOCUSED_MONITOR:-}" ]]; then
    for i in $AEROSAPCE_WORKSPACE_FOCUSED_MONITOR; do
      sketchybar --set space."$i" display="$AEROSPACE_FOCUSED_MONITOR"
    done
  fi
  
  if [[ -n "${AEROSPACE_EMPTY_WORKESPACE:-}" ]]; then
    for i in $AEROSPACE_EMPTY_WORKESPACE; do
      sketchybar --set space."$i" display=0
    done
  fi
  
  sketchybar --set space."$AEROSPACE_FOCUSED_WORKSPACE" display="$AEROSPACE_FOCUSED_MONITOR"
fi
