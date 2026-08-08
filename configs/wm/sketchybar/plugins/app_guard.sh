#!/bin/bash

# 常時起動していてほしいアプリの死活監視。expected_apps.conf に列挙したものが
# 落ちていれば親アイコンを赤い警告にする。すべて起動中なら緑のチェック。
# クリックでポップアップを開くと全アプリの稼働状況を一覧表示し (items/app_guard.sh)、
# 落ちている行のクリックでそれだけ再起動する (relaunch サブコマンド)。

source "$HOME/.config/sketchybar-colors.sh"

ITEM="app_guard"
CONF="$CONFIG_DIR/expected_apps.conf"

# conf を読み、name/pattern/relaunch の 3 配列に展開する。
# 配列の添字は items/app_guard.sh が作るポップアップ行 app_guard.<idx> と一致する。
names=()
patterns=()
relaunches=()
if [ -f "$CONF" ]; then
  while IFS='|' read -r name pattern relaunch; do
    name="$(echo "$name" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    pattern="$(echo "$pattern" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    relaunch="$(echo "$relaunch" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    [ -z "$name" ] && continue
    case "$name" in \#*) continue ;; esac
    [ -z "$pattern" ] && continue
    names+=("$name")
    patterns+=("$pattern")
    relaunches+=("$relaunch")
  done <"$CONF"
fi

# 稼働状況を確認し、親アイコンと各ポップアップ行をまとめて更新する。
update() {
  missing=()
  for i in "${!names[@]}"; do
    if pgrep -fi -- "${patterns[$i]}" >/dev/null 2>&1; then
      # 稼働中: 緑チェックの行。
      sketchybar --set "$ITEM.$i" icon=􀆅 icon.color="$GREEN" label.color="$LABEL_COLOR"
    else
      # 停止中: 赤バツの行 (クリックで再起動)。
      sketchybar --set "$ITEM.$i" icon=􀆄 icon.color="$RED" label.color="$RED"
      missing+=("${names[$i]}")
    fi
  done

  # 親: 全て起動中なら緑チェック、落ちていれば赤い警告 + 落ちている名前。
  if [ "${#missing[@]}" -eq 0 ]; then
    sketchybar --set "$ITEM" drawing=on \
      icon=􀁢 \
      icon.color="$GREEN" \
      label.drawing=off
  else
    label="$(
      IFS=' '
      echo "${missing[*]}"
    )"
    sketchybar --set "$ITEM" drawing=on \
      icon=􀇾 \
      icon.color="$RED" \
      label.drawing=on \
      label="$label" \
      label.color="$RED"
  fi
}

# relaunch <idx>: 指定アプリが落ちていれば再起動コマンドを実行して再描画する。
if [ "$1" = "relaunch" ]; then
  i="$2"
  if [ -n "${patterns[$i]:-}" ] && ! pgrep -fi -- "${patterns[$i]}" >/dev/null 2>&1; then
    cmd="${relaunches[$i]}"
    [ -n "$cmd" ] && eval "$cmd" >/dev/null 2>&1 &
  fi
  sleep 1
  update
  exit 0
fi

# refresh / 通常更新 (update_freq・イベント): 稼働状況を反映する。
update
