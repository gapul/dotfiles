#!/usr/bin/env bash
# pre-commit の `gitleaks protect --staged` は --no-verify で飛ばせるため、
# CI 側でも gitleaks detect で二重化する。gitleaks は devShell (nix develop ./nix)
# の PATH 前提。
#
# 速度: PR (GITHUB_BASE_REF あり) では base..HEAD の新規コミットだけ scan する。
# main push / scheduled / base 取得不可 / ローカルでは全履歴を detect する (保険)。
# PR が持ち込む秘密はその PR のコミットに出るので差分で十分、漏れは main の全履歴で拾う。
# 全履歴 fallback のため呼び出し側は shallow clone しないこと (GitHub なら fetch-depth: 0)。
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

common=(
  --config .gitleaks.toml
  --no-banner
  --redact
  --verbose
)

if [ -n "${GITHUB_BASE_REF:-}" ]; then
  git fetch --quiet origin "${GITHUB_BASE_REF}" 2>/dev/null || true
  if git rev-parse --verify --quiet "origin/${GITHUB_BASE_REF}" >/dev/null; then
    echo "gitleaks: PR 差分 (origin/${GITHUB_BASE_REF}..HEAD) を scan"
    exec gitleaks detect "${common[@]}" --log-opts="origin/${GITHUB_BASE_REF}..HEAD"
  fi
fi

echo "gitleaks: 全履歴を scan"
exec gitleaks detect "${common[@]}"
