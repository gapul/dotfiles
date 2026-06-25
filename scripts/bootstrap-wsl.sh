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
# 何度走らせても安全 (idempotent)。

set -euo pipefail

DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/gapul/dotfiles.git}"
DOTFILES_DIR="$HOME/.dotfiles"
SOPS_KEY="$HOME/.config/sops/age/keys.txt"
SSH_PRIV="$HOME/.ssh/id_ed25519"
SSH_PUB="$HOME/.ssh/id_ed25519.pub"
SSH_ALLOWED="$HOME/.ssh/allowed_signers"

log() { printf '\033[1;34m[bootstrap-wsl]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[bootstrap-wsl]\033[0m %s\n' "$*" >&2; }

# 1. apt 必須 (git for clone, curl for nix installer)
if ! command -v git >/dev/null || ! command -v curl >/dev/null; then
  log "Installing apt prerequisites (sudo パスワード入力あり)..."
  sudo apt-get update -y
  sudo apt-get install -y git curl xz-utils ca-certificates
fi

# 2. Determinate Nix (Linux)
if ! command -v nix >/dev/null && [ ! -x /nix/var/nix/profiles/default/bin/nix ]; then
  log "Installing Determinate Nix..."
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
    sh -s -- install linux --no-confirm
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi
if ! command -v nix >/dev/null; then
  export PATH="/nix/var/nix/profiles/default/bin:$PATH"
fi

# 3. dotfiles clone
if [ ! -d "$DOTFILES_DIR/.git" ]; then
  log "Cloning dotfiles..."
  git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
else
  log "dotfiles already present, pulling..."
  git -C "$DOTFILES_DIR" pull --rebase
fi

# 4. age 秘密鍵
if [ ! -f "$SOPS_KEY" ]; then
  mkdir -p "$(dirname "$SOPS_KEY")"
  chmod 700 "$(dirname "$SOPS_KEY")"
  err "age 秘密鍵が見つかりません:"
  err "  Bitwarden 等から $SOPS_KEY に貼り付けて save、本スクリプト再実行."
  exit 1
fi
chmod 600 "$SOPS_KEY"
log "SOPS age key OK"

# 5. SSH 秘密鍵
if [ ! -f "$SSH_PRIV" ]; then
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  err "SSH 秘密鍵 ($SSH_PRIV) が見つかりません:"
  err "  Bitwarden 等から貼り付けて 'chmod 600 $SSH_PRIV' して再実行."
  exit 1
fi
chmod 600 "$SSH_PRIV"
ssh-keygen -y -f "$SSH_PRIV" > "$SSH_PUB"
chmod 644 "$SSH_PUB"
if [ ! -f "$SSH_ALLOWED" ]; then
  EMAIL=$(nix eval --raw -f "$DOTFILES_DIR/nix/user.nix" gitEmail 2>/dev/null || echo "92638132+gapul@users.noreply.github.com")
  echo "$EMAIL $(awk '{print $1, $2}' "$SSH_PUB")" > "$SSH_ALLOWED"
  chmod 600 "$SSH_ALLOWED"
fi
log "SSH key + allowed_signers OK"

# 6. home-manager switch (WSL attr)
log "home-manager switch (.#$(whoami)-wsl)..."
nix run home-manager/release-25.05 -- switch \
  --flake "$DOTFILES_DIR/nix#$(whoami)-wsl" -b backup

log ""
log "完了! 新しいシェルを開いてください:"
log "  exec zsh"
log ""
log "追加の手動ステップ:"
log "  - GitHub に新鍵を追加:"
log "      gh ssh-key add ~/.ssh/id_ed25519.pub --title \"$(hostname)\""
log "      gh api -X POST /user/ssh_signing_keys -f title=\"$(hostname) (signing)\" -f key=\"\$(cat ~/.ssh/id_ed25519.pub)\""
log "  - /etc/wsl.conf に systemd 有効化等が必要なら別途設定"
