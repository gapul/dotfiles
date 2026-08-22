#!/bin/bash
export HOME=/Users/hermes
export PATH=/Users/hermes/.local/bin:/opt/homebrew/bin:/usr/bin:/bin
# 画像の vision 前処理を止める。ACP 経路は multimodal をテキストに潰すので
# 前処理は必ず失敗し、画像1枚ごとにエラーと数秒の無駄が出る。claude-acp が
# 本文中のパスから実ファイルを添付するので、前処理なしで画像は届く。
export HERMES_DISABLE_IMAGE_PREANALYSIS=1
cd /Users/hermes || exit 1
exec /Users/hermes/.local/bin/hermes gateway
