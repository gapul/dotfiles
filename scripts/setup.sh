#!/bin/bash

# ドットファイル管理システム - 初期セットアップスクリプト
# 新しい環境でのドットファイル管理システムの完全セットアップ

set -e  # エラー時に停止

# 色付きメッセージ用の定数
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ログ関数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 設定
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="$HOME"

# 必要なディレクトリの作成
setup_directories() {
    log_info "必要なディレクトリを作成しています..."
    
    local directories=(
        "$DOTFILES_DIR/configs/zsh"
        "$DOTFILES_DIR/configs/git"
        "$DOTFILES_DIR/configs/vim"
        "$DOTFILES_DIR/configs/others"
        "$DOTFILES_DIR/backups"
    )
    
    for dir in "${directories[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log_info "ディレクトリを作成しました: $dir"
        fi
    done
}

# 既存ドットファイルの configs ディレクトリへのコピー
copy_existing_dotfiles() {
    log_info "既存のドットファイルを configs ディレクトリにコピーしています..."
    
    # Zsh関連
    if [[ -f "$HOME_DIR/.zshrc" ]]; then
        cp "$HOME_DIR/.zshrc" "$DOTFILES_DIR/configs/zsh/.zshrc"
        log_info ".zshrc をコピーしました"
    fi
    
    if [[ -f "$HOME_DIR/.zprofile" ]]; then
        cp "$HOME_DIR/.zprofile" "$DOTFILES_DIR/configs/zsh/.zprofile"
        log_info ".zprofile をコピーしました"
    fi
    
    # Git関連
    if [[ -f "$HOME_DIR/.gitconfig" ]]; then
        cp "$HOME_DIR/.gitconfig" "$DOTFILES_DIR/configs/git/.gitconfig"
        log_info ".gitconfig をコピーしました"
    fi
    
    # その他
    if [[ -f "$HOME_DIR/.condarc" ]]; then
        cp "$HOME_DIR/.condarc" "$DOTFILES_DIR/configs/others/.condarc"
        log_info ".condarc をコピーしました"
    fi
    
    if [[ -f "$HOME_DIR/.claude.json" ]]; then
        cp "$HOME_DIR/.claude.json" "$DOTFILES_DIR/configs/others/.claude.json"
        log_info ".claude.json をコピーしました"
    fi
    
    if [[ -f "$HOME_DIR/.vimrc" ]]; then
        cp "$HOME_DIR/.vimrc" "$DOTFILES_DIR/configs/vim/.vimrc"
        log_info ".vimrc をコピーしました"
    fi
}

# デフォルト設定ファイルの作成
create_default_configs() {
    log_info "デフォルト設定ファイルを作成しています..."
    
    # デフォルト .zshrc
    if [[ ! -f "$DOTFILES_DIR/configs/zsh/.zshrc" ]]; then
        cat > "$DOTFILES_DIR/configs/zsh/.zshrc" << 'EOF'
# Zsh configuration managed by dotfiles

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Oh My Zsh configuration
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"

# Plugins
plugins=(
    git
    zsh-autosuggestions
    zsh-syntax-highlighting
    brew
    macos
)

source $ZSH/oh-my-zsh.sh

# User configuration
export LANG=en_US.UTF-8
export EDITOR='vim'

# Aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'

# Custom functions
# Add your custom functions here

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
EOF
        log_info "デフォルト .zshrc を作成しました"
    fi
    
    # デフォルト .gitconfig
    if [[ ! -f "$DOTFILES_DIR/configs/git/.gitconfig" ]]; then
        cat > "$DOTFILES_DIR/configs/git/.gitconfig" << 'EOF'
[user]
    name = Your Name
    email = your.email@example.com

[core]
    editor = vim
    autocrlf = input
    safecrlf = true

[alias]
    st = status
    co = checkout
    br = branch
    ci = commit
    cm = commit -m
    lg = log --oneline --graph --decorate --all
    unstage = reset HEAD --

[color]
    ui = auto

[push]
    default = simple

[pull]
    rebase = false
EOF
        log_info "デフォルト .gitconfig を作成しました"
    fi
}

# Git リポジトリの初期化
init_git_repo() {
    if [[ ! -d "$DOTFILES_DIR/.git" ]]; then
        log_info "Git リポジトリを初期化しています..."
        
        cd "$DOTFILES_DIR"
        git init
        
        # .gitignore の作成
        cat > .gitignore << 'EOF'
# macOS
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db

# Backup files
backups/

# Temporary files
*.tmp
*.temp
*.swp
*.swo
*~

# IDE
.vscode/
.idea/

# Logs
*.log
EOF
        
        git add .
        git commit -m "Initial commit: dotfiles management system"
        
        log_success "Git リポジトリを初期化しました"
    else
        log_info "Git リポジトリは既に存在します"
    fi
}

# システム情報の確認
check_system() {
    log_info "システム情報を確認しています..."
    
    echo "OS: $(uname -s)"
    echo "Version: $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo "Shell: $SHELL"
    
    # Homebrew の確認
    if command -v brew >/dev/null 2>&1; then
        echo "Homebrew: $(brew --version | head -n1)"
    else
        log_warning "Homebrew がインストールされていません"
    fi
    
    # Oh My Zsh の確認
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        echo "Oh My Zsh: インストール済み"
    else
        log_warning "Oh My Zsh がインストールされていません"
    fi
}

# 使用方法の表示
show_usage() {
    cat << 'EOF'
ドットファイル管理システムのセットアップが完了しました！

次のステップ:

1. 設定ファイルの編集:
   configs/ ディレクトリ内のファイルを編集してください
   - configs/zsh/.zshrc      : Zsh設定
   - configs/git/.gitconfig  : Git設定
   - configs/others/         : その他の設定

2. インストールの実行:
   ./install.sh

3. バックアップの作成:
   ./backup.sh

4. Git での管理:
   git add .
   git commit -m "Update dotfiles"

利用可能なコマンド:
- ./install.sh    : ドットファイルをインストール
- ./backup.sh     : 現在の設定をバックアップ
- ./restore.sh    : バックアップから復元
- ./setup.sh      : このセットアップスクリプト

詳細は README.md をご覧ください。
EOF
}

# メイン処理
main() {
    log_info "ドットファイル管理システムの初期セットアップを開始します"
    
    check_system
    echo
    
    setup_directories
    copy_existing_dotfiles
    create_default_configs
    init_git_repo
    
    log_success "セットアップが完了しました！"
    echo
    show_usage
}

# スクリプトが直接実行された場合のみmainを呼び出す
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi