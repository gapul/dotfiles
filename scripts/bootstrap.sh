#!/usr/bin/env bash
#
# 新しい Mac で 0 → 1 セットアップ。
# 想定: 工場出荷状態 + Apple ID ログイン + FileVault on 直後。
#
# 流れ:
#   1. Xcode Command Line Tools (git/curl/etc. のため)
#   2. Determinate Nix install
#   3. ~/dotfiles を git clone
#   4. age 秘密鍵を ~/.config/sops/age/keys.txt に配置 (手動 paste 待ち)
#   5. nix run nix-darwin -- switch
#   6. 各 third-party brew tap を trust
#   7. nix run home-manager -- switch
#   8. brew uninstall (Nix側に移行した重複)
#
# 何度走らせても安全 (idempotent)。

set -euo pipefail

log() { printf '\033[1;34m[bootstrap]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[bootstrap]\033[0m %s\n' "$*" >&2; }

DOTFILES_REPO="https://github.com/gapul/dotfiles.git"
DOTFILES_DIR="$HOME/dotfiles"
SOPS_KEY="$HOME/.config/sops/age/keys.txt"

# 1. Xcode CLT
if ! xcode-select -p >/dev/null 2>&1; then
  log "Installing Xcode Command Line Tools (GUI が立ち上がる)..."
  xcode-select --install || true
  until xcode-select -p >/dev/null 2>&1; do
    sleep 5
    log "  ... 待機中"
  done
fi
log "Xcode CLT OK"

# 2. Determinate Nix
if ! command -v nix >/dev/null && [ ! -x /nix/var/nix/profiles/default/bin/nix ]; then
  log "Installing Determinate Nix..."
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
    sh -s -- install --no-confirm
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
else
  log "Determinate Nix already installed"
fi

# Ensure nix in PATH for the rest of this script
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
  err "  Bitwarden の 'SOPS age key (yuki@laptop)' Secure Note を開き、"
  err "  Notes の中身を $SOPS_KEY に貼り付けて save してください。"
  err "  終わったら本スクリプトを再実行 (それ以降から resume)."
  exit 1
fi
chmod 600 "$SOPS_KEY"
log "SOPS age key OK"

# 5. system 設定 (sudo パスワード要)
log "darwin-rebuild switch (sudo パスワード入力あり)..."
sudo nix run nix-darwin/nix-darwin-25.05 -- switch --flake "$DOTFILES_DIR/nix#yuki"

# 6. 第三者 tap の cask 信頼
log "Trusting third-party brew taps..."
for tap in nikitabobko/tap theboredteam/boring-notch pear-devs/pear gapul/openutau \
           deskflow/tap gerlero/openfoam imshuhao/kdeconnect felixkratz/formulae \
           finnvoor/tools gapul/zrythm homebrew-zathura/zathura infisical/get-cli \
           jakehilborn/jakehilborn jpmhouston/bananameterlabs pomdtr/tap \
           riscv-software-src/riscv supabase/tap; do
  brew trust "$tap" 2>/dev/null || true
done

# 7. home-manager switch (yuki 権限で実行、sudo 禁止)
log "home-manager switch..."
nix run home-manager/release-25.05 -- switch --flake "$DOTFILES_DIR/nix#yuki" -b backup

# 8. brew 重複の uninstall (Nix 管理に移行済のもの)
log "Cleaning duplicates installed by both brew and Nix..."
brew uninstall starship fzf atuin 2>/dev/null || true

log "完了! 新しいシェルを開いてください:"
log "  exec zsh"
