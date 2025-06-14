#!/bin/bash

# ソフトウェアインストールスクリプト
# Weztermカスタマイズに必要なソフトウェアをインストールします

set -e
set -u
set -o pipefail

# 色付きメッセージ用の定数
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Oh My Zshのインストール
install_oh_my_zsh() {
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        log_info "Oh My Zshは既にインストールされています"
        return
    fi
    
    log_info "Oh My Zshをインストールしています..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    log_success "Oh My Zshのインストールが完了しました"
}

# 必要なBrewパッケージのインストール
install_brew_packages() {
    local packages=(
        "wezterm"      # ターミナルエミュレータ
        "starship"     # プロンプト
        "git"          # バージョン管理
        "tree"         # ディレクトリ表示
        "jq"           # JSON処理
    )
    
    log_info "必要なパッケージを確認・インストールしています..."
    
    for package in "${packages[@]}"; do
        if brew list "$package" >/dev/null 2>&1; then
            log_info "$package は既にインストールされています"
        else
            log_info "$package をインストールしています..."
            brew install "$package"
            log_success "$package のインストールが完了しました"
        fi
    done
}

# HackGenフォントの確認
check_hackgen_font() {
    log_info "HackGenフォントの確認中..."
    
    # システムフォントディレクトリの確認（macOS）
    local font_dirs=(
        "$HOME/Library/Fonts"
        "/Library/Fonts"
        "/System/Library/Fonts"
    )
    
    for dir in "${font_dirs[@]}"; do
        if [[ -d "$dir" ]] && find "$dir" -name "*HackGen*" -type f 2>/dev/null | grep -q .; then
            log_success "HackGenフォントが見つかりました: $dir"
            return
        fi
    done
    
    log_warning "HackGenフォントが見つかりませんでした"
    log_info "以下からダウンロードしてインストールしてください:"
    log_info "https://github.com/yuru7/HackGen/releases"
}

# メイン処理
main() {
    log_info "Wezterm環境のソフトウェアセットアップを開始します"
    echo
    
    # 必要なパッケージのインストール
    install_brew_packages
    echo
    
    # Oh My Zshのインストール
    install_oh_my_zsh
    echo
    
    # HackGenフォントの確認
    check_hackgen_font
    echo
    
    log_success "ソフトウェアセットアップが完了しました！"
    echo
    log_info "次のステップ:"
    log_info "1. ./install.sh を実行してドットファイルを設定"
    log_info "2. Weztermを再起動して設定を反映"
}

# コマンドライン引数の処理
case "${1:-}" in
    -h|--help)
        echo "使用方法: $0"
        echo "Wezterm環境に必要なソフトウェアをインストールします"
        exit 0
        ;;
    "")
        main
        ;;
    *)
        log_error "不明なオプション: $1"
        exit 1
        ;;
esac