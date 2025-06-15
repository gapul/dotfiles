#!/bin/bash

# ドットファイル管理システム - インストールラッパー
# scripts/install.sh への簡単なアクセスを提供

exec "$(dirname "$0")/scripts/install.sh" "$@"