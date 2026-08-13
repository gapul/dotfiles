#!/bin/bash
# 妹用の gateway。HOME を分けることで単一プロファイルとして動き、
# api_server が自分のポート(8791)を持てる。
export HOME=/Users/hermes/imouto-home
export PATH=/Users/hermes/.local/bin:/opt/homebrew/bin:/usr/bin:/bin
export HERMES_ACCEPT_HOOKS=1
cd /Users/hermes/imouto-home || exit 1
exec /Users/hermes/.local/bin/hermes gateway
