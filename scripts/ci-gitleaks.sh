#!/usr/bin/env bash
# pre-commit の `gitleaks protect --staged` は --no-verify で飛ばせるため、
# CI 側では全コミット履歴を detect して二重化する。
# gitleaks は devShell (nix develop ./nix) の PATH 前提。全履歴が必要なので
# 呼び出し側は shallow clone しないこと (GitHub なら fetch-depth: 0)。
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

exec gitleaks detect \
  --config .gitleaks.toml \
  --no-banner \
  --redact \
  --verbose
