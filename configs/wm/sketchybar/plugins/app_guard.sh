#!/bin/bash

# 常時起動していてほしいアプリの死活監視。expected_apps.conf に列挙したものが
# 落ちていれば親アイコンを赤い警告にする。すべて起動中なら緑のチェック。
# クリックでポップアップを開くと全アプリの稼働状況を一覧表示し (items/app_guard.sh)、
# 落ちている行のクリックでそれだけ再起動する (relaunch サブコマンド)。
#
# 状態は 3 つある。「停止」と「実行ファイル無し」を分けているのは、後者が再起動で
# 直らないから。conf の 4 列目に実行ファイルを書いた行だけ、まずその解決を見る。

source "$HOME/.config/sketchybar-colors.sh"

ITEM="app_guard"
CONF="$CONFIG_DIR/expected_apps.conf"

# conf を読み、name/pattern/relaunch の 3 配列に展開する。
# 配列の添字は items/app_guard.sh が作るポップアップ行 app_guard.<idx> と一致する。
names=()
patterns=()
relaunches=()
bins=()
if [ -f "$CONF" ]; then
  while IFS='|' read -r name pattern relaunch bin; do
    name="$(echo "$name" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    pattern="$(echo "$pattern" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    relaunch="$(echo "$relaunch" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    bin="$(echo "$bin" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    [ -z "$name" ] && continue
    case "$name" in \#*) continue ;; esac
    [ -z "$pattern" ] && continue
    names+=("$name")
    patterns+=("$pattern")
    relaunches+=("$relaunch")
    bins+=("$bin")
  done <"$CONF"
fi

# 4 列目に書かれた実行ファイルが今も在るか。/ 始まりは絶対パス、それ以外は PATH から引く。
# 空欄なら判定しない (その行は従来どおり pgrep だけを見る)。
bin_missing() {
  local bin="$1"
  [ -z "$bin" ] && return 1
  case "$bin" in
    /*) [ -x "$bin" ] && return 1 || return 0 ;;
    *) command -v -- "$bin" >/dev/null 2>&1 && return 1 || return 0 ;;
  esac
}

# 稼働状況を確認し、親アイコンと各ポップアップ行をまとめて更新する。
update() {
  missing=()
  broken=()
  for i in "${!names[@]}"; do
    if bin_missing "${bins[$i]}"; then
      # 実行ファイルが無い: 再起動しても直らないので、停止とは別の見た目にする。
      # 黄色の三角 + 「(実行ファイル無し)」。パスが動いたか、パッケージが消えたか。
      sketchybar --set "$ITEM.$i" icon=􀇾 icon.color="$YELLOW" \
        label="${names[$i]} (実行ファイル無し)" label.color="$YELLOW"
      broken+=("${names[$i]}")
    elif pgrep -fi -- "${patterns[$i]}" >/dev/null 2>&1; then
      # 稼働中: 緑チェックの行。
      sketchybar --set "$ITEM.$i" icon=􀆅 icon.color="$GREEN" \
        label="${names[$i]}" label.color="$LABEL_COLOR"
    else
      # 停止中: 赤バツの行 (クリックで再起動)。
      sketchybar --set "$ITEM.$i" icon=􀆄 icon.color="$RED" \
        label="${names[$i]}" label.color="$RED"
      missing+=("${names[$i]}")
    fi
  done

  # 親: 全て起動中なら緑チェック、落ちていれば赤い警告 + 落ちている名前。
  if [ "${#missing[@]}" -eq 0 ] && [ "${#broken[@]}" -eq 0 ]; then
    sketchybar --set "$ITEM" drawing=on \
      icon=􀁢 \
      icon.color="$GREEN" \
      label.drawing=off
  elif [ "${#broken[@]}" -ne 0 ]; then
    # 実行ファイル無しを優先して出す。停止は放っておけば直ることもあるが、こちらは
    # 設定か配置が壊れているので人が見るまで直らない。
    label="$(
      IFS=' '
      echo "${broken[*]}"
    )"
    sketchybar --set "$ITEM" drawing=on \
      icon=􀇾 \
      icon.color="$YELLOW" \
      label.drawing=on \
      label="$label" \
      label.color="$YELLOW"
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
  # 実行ファイルが無い行は再起動しても無意味なので何もしない (表示の更新だけ)。
  if [ -n "${patterns[$i]:-}" ] && ! bin_missing "${bins[$i]:-}" &&
    ! pgrep -fi -- "${patterns[$i]}" >/dev/null 2>&1; then
    cmd="${relaunches[$i]}"
    [ -n "$cmd" ] && eval "$cmd" >/dev/null 2>&1 &
  fi
  sleep 1
  update
  exit 0
fi

# refresh / 通常更新 (update_freq・イベント): 稼働状況を反映する。
update
