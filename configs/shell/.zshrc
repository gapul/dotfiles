# ===== PATH設定 =====
export PATH=$PATH:/Users/yuki/Library/Android/sdk/platform-tools
export PATH=$HOME/.nodebrew/current/bin:$PATH

# ===== エイリアス =====
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'

# Git関連エイリアス
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'

# 便利なエイリアス
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# 開発関連エイリアス
alias py='python3'
alias pip='pip3'
alias serve='python3 -m http.server 8000'

# Docker関連エイリアス
alias d='docker'
alias dc='docker-compose'
alias dps='docker ps'
alias di='docker images'

# ドットファイル管理関連
alias dotfiles='cd ~/dotfiles'
alias dots='cd ~/dotfiles && code .'

# ===== 便利な関数 =====
# ディレクトリ作成と移動を同時に行う
mkcd() {
    mkdir -p "$1" && cd "$1"
}

# ファイル検索
ff() {
    find . -name "*$1*" -type f
}

# プロセス検索
psg() {
    ps aux | grep "$1" | grep -v grep
}

# ===== Zsh設定 =====
# 履歴設定
HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.zsh_history

# Zshオプション
setopt HIST_IGNORE_DUPS      # 重複するコマンドを履歴に保存しない
setopt HIST_IGNORE_SPACE     # スペースで始まるコマンドを履歴に保存しない
setopt SHARE_HISTORY         # 履歴を他のzshプロセスと共有
setopt AUTO_PUSHD            # cd時に自動的にpushdする
setopt PUSHD_IGNORE_DUPS     # 重複するディレクトリをpushdしない

# ===== プロンプト初期化 =====
eval "$(starship init zsh)"
