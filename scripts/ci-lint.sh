#!/usr/bin/env bash
# pre-commit に含めない enforced 外リンタをまとめて実行する。
# omnix の devshell custom step (om ci) と GitHub 以外の CI からも同一に呼べるよう、
# 全ツールは devShell (nix develop ./nix) の PATH 前提で叩く。
# - just --summary : Justfile パース検証 (整形は just バージョン依存のため gate にしない)
# - statix         : Nix アンチパターン (repeated_keys は誤検出のため .statix.toml で除外)
# - shellcheck     : 全 .sh を error 重大度で gate (warning/info は既存資産が多く除外)
# - stylua         : nvim 配下の lua 整形 (uosc/yazi 等 vendored は対象外)
# - taplo/jq/yq    : toml/json/yaml の構文検証 (設定破損の即検知)
# - actionlint     : GitHub Actions workflow の文法/式チェック
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

echo "==> just --summary (Justfile パース検証)"
just --summary

echo "==> statix check (Nix アンチパターン)"
statix check -c .statix.toml nix

echo "==> shellcheck (全 .sh の error gate)"
git ls-files -z '*.sh' | xargs -0 shellcheck -S error

echo "==> stylua --check (nvim lua 整形)"
stylua --check configs/editors/nvim/

echo "==> taplo check (TOML 構文)"
git ls-files -z '*.toml' | xargs -0 taplo check

echo "==> jq empty (JSON 構文)"
git ls-files -z '*.json' | xargs -0 jq empty

echo "==> yq (YAML 構文)"
git ls-files -z '*.yml' '*.yaml' | xargs -0 yq -e '.'

echo "==> actionlint (GitHub Actions workflow)"
actionlint -color

echo "lint すべて通過"
