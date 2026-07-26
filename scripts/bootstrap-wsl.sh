#!/usr/bin/env bash
#
# WSL2 (Ubuntu 等) 上で 0→1 セットアップ。
# 想定: Windows + WSL2 fresh install 直後。
#
# 流れ:
#   1. apt 基本ツール
#   2. Determinate Nix install (Linux 用)
#   3. dotfiles clone
#   4. age 秘密鍵 paste 待ち (~/.config/sops/age/keys.txt)
#   5. SSH 秘密鍵 paste 待ち + .pub 再生成 + allowed_signers
#   6. home-manager switch (.#<username>-wsl)
#
# 定数・ログ・鍵受け取り・Nix install は scripts/lib/common.sh に集約。
# 何度走らせても安全 (idempotent)。

set -euo pipefail

# shellcheck disable=SC2034  # source 後に common.sh が参照する
COMMON_LOG_LABEL="bootstrap-wsl"
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# 1. apt 必須 (git for clone, curl for nix installer)
if ! command -v git >/dev/null || ! command -v curl >/dev/null; then
  log "Installing apt prerequisites (sudo パスワード入力あり)..."
  sudo apt-get update -y
  sudo apt-get install -y git curl xz-utils ca-certificates
fi

# 2. Determinate Nix (Linux)
install_nix linux

# 3. dotfiles clone
ensure_dotfiles

# 4. age 秘密鍵
require_age_key

# 5. SSH 秘密鍵
require_ssh_key

# 6. home-manager switch (WSL attr)
hm_switch "$(whoami)-wsl"

log ""
log "完了! 新しいシェルを開いてください:"
log "  exec zsh"
log ""
log "追加の手動ステップ:"
log "  - GitHub に新鍵を追加:"
log "      gh ssh-key add ~/.ssh/id_ed25519.pub --title \"$(hostname)\""
log "      gh api -X POST /user/ssh_signing_keys -f title=\"$(hostname) (signing)\" -f key=\"\$(cat ~/.ssh/id_ed25519.pub)\""
log "  - /etc/wsl.conf に systemd 有効化等が必要なら別途設定"
