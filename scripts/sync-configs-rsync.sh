#!/usr/bin/env bash
#
# 制限環境(non-root + Nix 不可)の SSH 接続先に、最小限の config だけ
# rsync で送る。nvim / git / zsh の基本だけ。
#
# 使い方:
#   sync-configs-rsync.sh user@host [--full]
#
# --full なら configs/* 全部送る (容量注意、git/yazi/calcurse 等含む)
# 既定は nvim + zsh + git のみ (~5MB)

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <user@host> [--full]" >&2
  exit 1
fi

HOST="$1"
MODE="${2:-minimal}"
SRC="$HOME/.dotfiles/configs"
EMAIL="${GIT_EMAIL:-92638132+gapul@users.noreply.github.com}"
NAME="${GIT_NAME:-gapul}"

log() { printf '\033[1;34m[sync-rsync]\033[0m %s\n' "$*"; }

# 1. nvim 設定 (必須)
log "rsync nvim → $HOST:~/.config/nvim/"
ssh "$HOST" 'mkdir -p ~/.config'
rsync -avz --delete "$SRC/editors/nvim/" "$HOST:.config/nvim/"

# 2. minimal zsh snippet (.zshrc.local に追記、源 .zshrc は触らない)
log "Installing minimal zsh snippet → ~/.zshrc.local"
ssh "$HOST" 'cat > ~/.zshrc.local' <<'ZSH'
# rsync-injected minimal config (dotfiles 完全 deploy ではない)
export EDITOR=nvim
export PAGER=less
alias ll='ls -la'
alias la='ls -lA'
alias g='git'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git pull'
alias ..='cd ..'
alias ...='cd ../..'
# vi keybind
bindkey -v 2>/dev/null
ZSH
# .zshrc に source 行を入れる(冪等)
ssh "$HOST" "grep -q '\.zshrc\.local' ~/.zshrc 2>/dev/null || echo '[ -f ~/.zshrc.local ] && source ~/.zshrc.local' >> ~/.zshrc"

# 3. git global config
log "Setting git user/email + sane defaults on remote"
ssh "$HOST" "
  git config --global user.name '$NAME'
  git config --global user.email '$EMAIL'
  git config --global init.defaultBranch main
  git config --global pull.rebase true
  git config --global push.autoSetupRemote true
"

# 4. --full なら他の configs も
if [[ "$MODE" == "--full" ]]; then
  log "Full mode: yazi / zellij / calcurse も rsync"
  for d in cli/yazi terminals/zellij cli/calcurse; do
    rsync -avz --delete "$SRC/$d/" "$HOST:.config/$(basename "$d")/" 2>/dev/null || true
  done
fi

log "完了"
log "remote で 'exec zsh' で reload、または再ログイン"
