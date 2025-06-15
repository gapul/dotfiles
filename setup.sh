#!/bin/bash

# ドットファイル管理システム - セットアップラッパー
# scripts/setup.sh への簡単なアクセスを提供

exec "$(dirname "$0")/scripts/setup.sh" "$@"