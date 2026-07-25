#!/bin/bash

# 常時起動していてほしいアプリの死活監視。expected_apps.conf に列挙したものが
# 落ちていれば警告アイコンを出し、クリックで再起動する。すべて起動中なら非表示。

source "$CONFIG_DIR/colors.sh"

CONF="$CONFIG_DIR/expected_apps.conf"

# conf を読み、name/pattern/relaunch の 3 配列に展開する。
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
  done < "$CONF"
fi

# クリック: 落ちているものだけ再起動コマンドを実行する。
if [ "$1" = "click" ]; then
  for i in "${!names[@]}"; do
    if ! pgrep -fi -- "${patterns[$i]}" >/dev/null 2>&1; then
      cmd="${relaunches[$i]}"
      [ -n "$cmd" ] && eval "$cmd" >/dev/null 2>&1 &
    fi
  done
  sleep 1
  exec "$0"   # 起動を反映して再描画
fi

# 死活チェック。落ちている表示名を集める。
missing=()
for i in "${!names[@]}"; do
  if ! pgrep -fi -- "${patterns[$i]}" >/dev/null 2>&1; then
    missing+=("${names[$i]}")
  fi
done

# 全て起動中なら緑のチェック、落ちていれば赤い警告 + 落ちている名前。
if [ "${#missing[@]}" -eq 0 ]; then
  sketchybar --set "$NAME" drawing=on \
    icon=􀁢 \
    icon.color="$GREEN" \
    label.drawing=off
else
  label="$(IFS=' '; echo "${missing[*]}")"
  sketchybar --set "$NAME" drawing=on \
    icon=􀇾 \
    icon.color="$RED" \
    label.drawing=on \
    label="$label" \
    label.color="$RED"
fi
