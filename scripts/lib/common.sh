#!/usr/bin/env bash
# bootstrap 系スクリプトが source する共有ライブラリ。単体実行はしない。
#
# 目的: bootstrap.sh / bootstrap-linux.sh / bootstrap-wsl.sh に三重コピーされていた
#       定数・ログ関数・鍵受け取り・Nix install を1箇所に集約する。
#       「repo URL / メール / NixOS バージョンを変える」= このファイルだけ直せば済む。
#
# 使い方 (各 bootstrap の冒頭):
#   COMMON_LOG_LABEL="bootstrap-linux"   # 省略時 bootstrap
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

# ── 定数 (真実の源。変更はここ1箇所) ─────────────────────────
# いずれも呼び出し側で環境変数から上書き可能 (?= 相当の :- 展開)。
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/gapul/dotfiles.git}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
SOPS_KEY="${SOPS_KEY:-$HOME/.config/sops/age/keys.txt}"
SSH_PRIV="${SSH_PRIV:-$HOME/.ssh/id_ed25519}"
SSH_PUB="${SSH_PUB:-$HOME/.ssh/id_ed25519.pub}"
SSH_ALLOWED="${SSH_ALLOWED:-$HOME/.ssh/allowed_signers}"

# Nix channel refs (NixOS リリースを上げる時はここだけ)
NIX_DARWIN_REF="${NIX_DARWIN_REF:-nix-darwin/nix-darwin-26.05}"
HOME_MANAGER_REF="${HOME_MANAGER_REF:-home-manager/release-26.05}"

# Determinate Nix installer (immutable tag + audited sha256)。
# 配布スクリプト自身が platform 別 Nix バイナリも検証する。
NIX_INSTALLER_URL="${NIX_INSTALLER_URL:-https://install.determinate.systems/nix/tag/v3.21.8}"
NIX_INSTALLER_SHA="${NIX_INSTALLER_SHA:-efda20b2cc3a012ea750d670e74670c155da3c291bc1021c5951a2310cbf2647}"

# git 署名メールの最終 fallback (通常は nix/user.nix gitEmail が優先される)
DEFAULT_GIT_EMAIL="${DEFAULT_GIT_EMAIL:-92638132+gapul@users.noreply.github.com}"

# ── ログ ─────────────────────────────────────────────────
: "${COMMON_LOG_LABEL:=bootstrap}"
log() { printf '\033[1;34m[%s]\033[0m %s\n' "$COMMON_LOG_LABEL" "$*"; }
err() { printf '\033[1;31m[%s]\033[0m %s\n' "$COMMON_LOG_LABEL" "$*" >&2; }

# ── Nix install ──────────────────────────────────────────
_verify_sha256() { # <file> <expected-hash>
  if command -v shasum >/dev/null; then
    printf '%s  %s\n' "$2" "$1" | shasum -a 256 -c -
  else
    printf '%s  %s\n' "$2" "$1" | sha256sum -c -
  fi
}

# install_nix [plan]  plan = determinate の install サブコマンド引数 (linux 等。mac は空)
install_nix() {
  local plan="${1:-}"
  if command -v nix >/dev/null || [ -x /nix/var/nix/profiles/default/bin/nix ]; then
    log "Determinate Nix already installed"
  else
    log "Installing Determinate Nix..."
    local installer
    installer=$(mktemp)
    curl --proto '=https' --tlsv1.2 -fsSL "$NIX_INSTALLER_URL" -o "$installer"
    _verify_sha256 "$installer" "$NIX_INSTALLER_SHA"
    # shellcheck disable=SC2086  # plan は空なら引数ゼロ個で渡す意図
    sh "$installer" install $plan --no-confirm
    rm -f "$installer"
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi
  # 残り処理のため nix を PATH に確保
  command -v nix >/dev/null || export PATH="/nix/var/nix/profiles/default/bin:$PATH"
}

# ── dotfiles ─────────────────────────────────────────────
ensure_dotfiles() {
  if [ ! -d "$DOTFILES_DIR/.git" ]; then
    log "Cloning dotfiles..."
    git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
  else
    log "dotfiles already present, pulling..."
    git -C "$DOTFILES_DIR" pull --rebase
  fi
}

# ── 秘密鍵 (Bitwarden 等から paste 待ち) ──────────────────
require_age_key() {
  if [ ! -f "$SOPS_KEY" ]; then
    mkdir -p "$(dirname "$SOPS_KEY")"
    chmod 700 "$(dirname "$SOPS_KEY")"
    err "age 秘密鍵が見つかりません:"
    err "  Bitwarden 等で保管している age 秘密鍵を $SOPS_KEY に貼り付けて save、"
    err "  終わったら本スクリプトを再実行 (それ以降から resume)."
    exit 1
  fi
  chmod 600 "$SOPS_KEY"
  log "SOPS age key OK"
}

# SSH 秘密鍵を確認し、.pub 再生成 + allowed_signers を生成する。
require_ssh_key() {
  if [ ! -f "$SSH_PRIV" ]; then
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    err "SSH 秘密鍵 ($SSH_PRIV) が見つかりません:"
    err "  Bitwarden 等で保管している ed25519 秘密鍵を貼り付けて save、"
    err "  終わったら 'chmod 600 $SSH_PRIV' してから本スクリプトを再実行."
    exit 1
  fi
  chmod 600 "$SSH_PRIV"
  # .pub を秘密鍵から再生成 (古い不整合 .pub 残骸対策)
  ssh-keygen -y -f "$SSH_PRIV" >"$SSH_PUB"
  chmod 644 "$SSH_PUB"
  # allowed_signers (git の SSH 署名検証用)
  if [ ! -f "$SSH_ALLOWED" ]; then
    local email
    email=$(nix eval --raw -f "$DOTFILES_DIR/nix/user.nix" gitEmail 2>/dev/null || echo "$DEFAULT_GIT_EMAIL")
    echo "$email $(awk '{print $1, $2}' "$SSH_PUB")" >"$SSH_ALLOWED"
    chmod 600 "$SSH_ALLOWED"
  fi
  log "SSH key + allowed_signers OK"
}

# ── switch ───────────────────────────────────────────────
# home-manager switch。第1引数に flake attr (例: gapul-linux)
hm_switch() {
  log "home-manager switch (.#$1)..."
  nix run "$HOME_MANAGER_REF" -- switch --flake "$DOTFILES_DIR/nix#$1" -b backup
}

# darwin.nix の homebrew.taps を1行1tapで出力 (jq 不要。bootstrap.sh の
# 手書き tap 一覧を廃し、宣言と自動同期させるための単一 source)。
darwin_taps() {
  local user
  user=$(nix eval --raw -f "$DOTFILES_DIR/nix/user.nix" username 2>/dev/null || whoami)
  nix eval --raw \
    "$DOTFILES_DIR/nix#darwinConfigurations.$user.config.homebrew.taps" \
    --apply 'ts: builtins.concatStringsSep "\n" (map (t: t.name) ts)'
}
