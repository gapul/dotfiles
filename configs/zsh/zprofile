# ===== Homebrew設定 =====
eval "$(/opt/homebrew/bin/brew shellenv)"

# ===== PATH設定 =====
# Homebrew優先
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"

# ユーザーローカルbin
export PATH="$HOME/.local/bin:$PATH"

# Rust/Cargo
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

# Go
export GOPATH="$HOME/go"
export PATH="$GOPATH/bin:$PATH"

# Python/Poetry
export PATH="$HOME/.poetry/bin:$PATH"

# Node.js (n)
export N_PREFIX="$HOME/n"
export PATH="$N_PREFIX/bin:$PATH"

# ===== 環境変数 =====
# XDG Base Directory
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"

# macOS特有設定
export BROWSER='open'

# ===== セキュリティ設定 =====
# GPG TTY設定
export GPG_TTY=$(tty)

# SSH Agent設定
if [[ -z "$SSH_AUTH_SOCK" ]]; then
    eval "$(ssh-agent -s)" >/dev/null 2>&1
fi
