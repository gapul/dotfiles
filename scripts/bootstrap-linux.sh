#!/usr/bin/env bash
#
# 長期 Linux サーバー (自宅 NUC / VPS / 開発機) 用 0→1 セットアップ。
# 想定: Ubuntu / Debian / Fedora / Arch fresh install + sudo 権限あり。
#
# 流れ:
#   1. distro 判定 + 基本パッケージ install (curl/git/xz-utils)
#   2. Determinate Nix install (Linux)
#   3. dotfiles clone
#   4. age 秘密鍵 paste 待ち
#   5. SSH 秘密鍵 paste 待ち + .pub 再生成 + allowed_signers
#   6. home-manager switch (.#<username>-linux or -linux-aarch64)
#
# 定数・ログ・鍵受け取り・Nix install は scripts/lib/common.sh に集約。
# 何度走らせても安全 (idempotent)。

set -euo pipefail

# shellcheck disable=SC2034  # source 後に common.sh が参照する
COMMON_LOG_LABEL="bootstrap-linux"
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# 1. distro 判定 + 基本ツール
if ! command -v git >/dev/null || ! command -v curl >/dev/null; then
  log "Installing prerequisites (sudo required)..."
  if command -v apt-get >/dev/null; then
    sudo apt-get update -y && sudo apt-get install -y git curl xz-utils ca-certificates
  elif command -v dnf >/dev/null; then
    sudo dnf install -y git curl xz ca-certificates
  elif command -v pacman >/dev/null; then
    sudo pacman -Sy --noconfirm git curl xz ca-certificates
  else
    err "未知のディストロ。git + curl + xz を手動で install して再実行"
    exit 1
  fi
fi

# 2. Determinate Nix
install_nix linux

# 3. dotfiles clone
ensure_dotfiles

# 4. age 秘密鍵
require_age_key

# 5. SSH 秘密鍵
require_ssh_key

# 6. home-manager switch (arch で attr 切替)
arch=$(uname -m)
case "$arch" in
  x86_64)  ATTR="$(whoami)-linux" ;;
  aarch64) ATTR="$(whoami)-linux-aarch64" ;;
  *) err "未対応 arch: $arch"; exit 1 ;;
esac

hm_switch "$ATTR"

log ""
log "完了! 新しいシェルを開いてください: exec zsh"
