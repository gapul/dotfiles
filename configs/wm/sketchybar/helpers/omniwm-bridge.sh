#!/bin/bash
#
# OmniWM の IPC イベントを sketchybar のカスタムイベントに橋渡しする常駐スクリプト。
# launchd (omniwm-bridge agent) から KeepAlive で起動される。
#
# 旧 WM は自前の exec-and-forget でワークスペース変更イベントを発火していたが、
# omniwm には exec アクションが無いので、omniwmctl watch で購読して同じイベント名・
# 同じ環境変数名 (OMNIWM_FOCUSED_WORKSPACE / OMNIWM_PREV_WORKSPACE) に変換する。
# こうすると space_windows.sh 以下のウィジェットは WM がどちらでも無変更で動く。
#
# OmniWM が動いていない間は待機ループに入るだけ。

OW=/opt/homebrew/bin/omniwmctl

while :; do
  if pgrep -xq OmniWM && "$OW" ping >/dev/null 2>&1; then
    # active-workspace: ワークスペース切替 / windows-changed: ウィンドウの増減・移動
    # イベントごとに omniwm-event.sh が JSON を stdin で受けて発火する。
    # OmniWM 終了や IPC 停止で watch が抜けたら外側のループで再接続する。
    "$OW" watch active-workspace,windows-changed --exec "$HOME/.config/sketchybar/helpers/omniwm-event.sh"
  fi
  sleep 5
done
