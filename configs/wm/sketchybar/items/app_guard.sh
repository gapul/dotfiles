#!/bin/bash

# 常時起動していてほしいアプリが落ちていたら警告を出す item。
# 監視対象は expected_apps.conf。全て起動中でも緑チェックは常に表示し、
# クリックでポップアップに全アプリの稼働状況 (✓稼働 / ✗停止) を一覧表示する。
# 落ちている行をクリックするとそれだけ再起動する。

POPUP_OFF="sketchybar --set app_guard popup.drawing=off"

app_guard=(
  icon=􀁢
  icon.font="$FONT:Bold:$(scf 14.0)"
  icon.color=$GREEN
  label.font="$FONT:Semibold:$(scf 12.0)"
  label.color=$RED
  label.padding_left=$(sc 1.34)
  label.drawing=off
  script="$PLUGIN_DIR/app_guard.sh"
  update_freq=15
  # クリックでポップアップを開閉し、開いた瞬間に最新状態へ更新する。
  click_script="sketchybar --set app_guard popup.drawing=toggle; $PLUGIN_DIR/app_guard.sh refresh"
  popup.height=$(sc 30)
)

sketchybar --add item app_guard right \
  --set app_guard "${app_guard[@]}" \
  --subscribe app_guard system_woke front_app_switched

# expected_apps.conf の各アプリに対応するポップアップ行を作る。
# ラベル/アイコン色は plugins/app_guard.sh が稼働状況に応じて後から更新する。
CONF="$CONFIG_DIR/expected_apps.conf"
if [ -f "$CONF" ]; then
  i=0
  while IFS='|' read -r name pattern _; do
    name="$(echo "$name" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    pattern="$(echo "$pattern" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    [ -z "$name" ] && continue
    case "$name" in \#*) continue ;; esac
    [ -z "$pattern" ] && continue

    sketchybar --add item "app_guard.$i" popup.app_guard \
      --set "app_guard.$i" \
      icon=􀆅 \
      icon.font="$FONT:Bold:$(scf 12.0)" \
      icon.color="$GREEN" \
      label="$name" \
      label.font="$FONT:Semibold:$(scf 12.0)" \
      label.color="$LABEL_COLOR" \
      click_script="$PLUGIN_DIR/app_guard.sh relaunch $i; $POPUP_OFF"
    i=$((i + 1))
  done <"$CONF"
fi
