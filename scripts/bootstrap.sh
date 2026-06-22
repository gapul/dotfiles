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

# Fork した時はこの URL を自分の repo に変える(or nix/user.nix の dotfilesRepo を参照)
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/gapul/dotfiles.git}"
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

# 2.5. /nix ボリュームを起動序盤に確実にマウントさせる (Login Items 対策)
#
# Determinate のデフォルト構成:
#   - /nix ボリュームを FileVault 暗号化
#   - /etc/fstab に noauto を付与
#   - launchd デーモン org.nixos.darwin-store が遅延マウント
# 結果: Login Items の Ghostty / AeroSpace 等が起動した時点で /nix がまだマウントされず、
#       symlink 先 (/nix/store/...) が読めず config 読み込み失敗
#
# 対策: ボリューム復号化 + fstab から noauto 削除 → macOS automountd が起動序盤にマウント
# トレードオフ: Determinate 公式サポート外設定。セキュリティ的には FileVault でカバー済
#               (/nix の中身は公開バイナリなので二重暗号化に実害価値なし)
#
# 暗号化チェック
if diskutil apfs list 2>/dev/null | grep -A 6 "Nix Store" | grep -q "FileVault: *Yes"; then
  log "/nix ボリュームが暗号化されてます。Login Items 競合を避けるため復号化します..."
  # ボリュームパスワードを System keychain から取得
  NIX_VOL_PW=$(sudo security find-generic-password -s "Nix Store" -a "Nix Store" -w \
                /Library/Keychains/System.keychain 2>/dev/null || true)
  if [ -z "$NIX_VOL_PW" ]; then
    err "  System keychain に Nix Store のパスワードが見つかりません"
    err "  Keychain Access で 'Nix Store' エントリを開いて password を取り出してから手動で:"
    err "    sudo diskutil apfs decryptVolume \"Nix Store\""
    exit 1
  fi
  printf '%s' "$NIX_VOL_PW" | sudo diskutil apfs decryptVolume "Nix Store" -stdinpassphrase
  log "復号化完了 (AES ハードウェアアクセラレーションで一瞬で終わるはず)"
fi

# fstab の noauto を削除
if grep -q "noauto" /etc/fstab 2>/dev/null; then
  log "/etc/fstab から noauto を削除して起動時自動マウントを有効化..."
  sudo cp /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d_%H%M%S)"
  sudo sed -i '' 's/,noauto//' /etc/fstab
  log "  修正後: $(grep '/nix' /etc/fstab)"
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
  err "  Bitwarden 等で保管している自分の age 秘密鍵を、"
  err "  Notes の中身を $SOPS_KEY に貼り付けて save してください。"
  err "  終わったら本スクリプトを再実行 (それ以降から resume)."
  exit 1
fi
chmod 600 "$SOPS_KEY"
log "SOPS age key OK"

# 5. system 設定 (sudo パスワード要)
log "darwin-rebuild switch (sudo パスワード入力あり)..."
sudo nix run nix-darwin/nix-darwin-25.05 -- switch --flake "$DOTFILES_DIR/nix#$(whoami)"

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
nix run home-manager/release-25.05 -- switch --flake "$DOTFILES_DIR/nix#$(whoami)" -b backup

# 8. brew 重複の uninstall (Nix 管理に移行済のもの)
log "Cleaning duplicates installed by both brew and Nix..."
brew uninstall starship fzf atuin 2>/dev/null || true

# 9. uv tool で入れる CLI (brew/nix に無いもの)
log "Installing uv tools (gita, etc.)..."
uv tool install gita 2>&1 | tail -3 || true

# 10. ghq 配下の全 repo を gita に登録 (空でも安全)
if command -v gita >/dev/null && command -v ghq >/dev/null; then
  log "Registering ghq repos with gita..."
  ghq list -p 2>/dev/null | xargs -I {} gita add {} 2>&1 | tail -3 || true
fi

log "完了! 新しいシェルを開いてください:"
log "  exec zsh"
