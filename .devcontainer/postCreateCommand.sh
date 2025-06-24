#!/bin/bash
# GitHub Codespaces初期セットアップスクリプト
set -euo pipefail

echo "🚀 GitHub Codespaces dotfiles環境セットアップ開始"

# 色設定
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# 1. Nix環境初期化
log_info "Nix環境初期化"
if command -v nix >/dev/null 2>&1; then
    log_success "Nix インストール済み"
    
    # Nix設定
    mkdir -p ~/.config/nix
    cat > ~/.config/nix/nix.conf << EOF
experimental-features = nix-command flakes
trusted-users = vscode
EOF
    
    # プロファイル読み込み
    if [[ -f /etc/profile.d/nix.sh ]]; then
        source /etc/profile.d/nix.sh
    fi
    
    log_success "Nix設定完了"
else
    log_error "Nix インストールに失敗"
    exit 1
fi

# 2. Home Manager インストール
log_info "Home Manager セットアップ"
if ! command -v home-manager >/dev/null 2>&1; then
    # Home Manager用チャンネル追加
    nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
    nix-channel --update
    
    # Home Manager インストール
    nix-shell '<home-manager>' -A install
    log_success "Home Manager インストール完了"
else
    log_success "Home Manager 既にインストール済み"
fi

# 3. Codespaces用Nix設定作成
log_info "Codespaces用設定作成"
mkdir -p ~/.config/home-manager

cat > ~/.config/home-manager/home.nix << 'EOF'
{ config, pkgs, ... }:

{
  # State version
  home.stateVersion = "24.05";
  
  # User info
  home.username = "vscode";
  home.homeDirectory = "/home/vscode";
  
  # GitHub Codespaces環境用パッケージ
  home.packages = with pkgs; [
    # Development tools
    git
    gh
    starship
    zsh
    neovim
    
    # Nix tools
    nil
    nixpkgs-fmt
    nix-tree
    
    # Shell utilities
    jq
    yq-go
    bat
    eza
    fd
    ripgrep
    
    # Build tools
    just
    direnv
    
    # Security tools
    age
    sops
    
    # Node.js tools (Claude CLI用)
    nodejs_20
    npm-check-updates
  ];
  
  # Git設定
  programs.git = {
    enable = true;
    userName = "GitHub Codespaces";
    userEmail = "codespaces@github.com";
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = false;
      push.autoSetupRemote = true;
    };
  };
  
  # GitHub CLI設定
  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "https";
      editor = "nvim";
    };
  };
  
  # Starship prompt
  programs.starship = {
    enable = true;
    settings = {
      format = "$directory$git_branch$git_status$cmd_duration$line_break$character";
      directory = {
        style = "blue";
        truncation_length = 3;
      };
      git_branch = {
        format = "[$symbol$branch]($style) ";
        style = "bright-green";
      };
      character = {
        success_symbol = "[❯](purple)";
        error_symbol = "[❯](red)";
      };
    };
  };
  
  # Zsh設定
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    
    shellAliases = {
      ls = "eza";
      ll = "eza -la";
      cat = "bat";
      find = "fd";
      grep = "rg";
      
      # Git shortcuts
      g = "git";
      gs = "git status";
      ga = "git add";
      gc = "git commit";
      gp = "git push";
      gl = "git pull";
      
      # GitHub CLI shortcuts
      ghpr = "gh pr create";
      ghpv = "gh pr view";
      ghis = "gh issue create";
      
      # Dotfiles shortcuts
      rebuild = "home-manager switch";
      check = "nix flake check";
    };
    
    initExtra = ''
      # Codespaces環境変数
      export DOTFILES_ENVIRONMENT="codespaces"
      export DOTFILES_PLATFORM="linux"
      
      # 開発環境関数
      function dotfiles-rebuild() {
        echo "🔄 Rebuilding dotfiles configuration..."
        cd /workspaces/dotfiles
        home-manager switch --flake .#codespaces
      }
      
      function dotfiles-health() {
        echo "🏥 Dotfiles health check..."
        cd /workspaces/dotfiles
        ./system-health-check.sh
      }
    '';
  };
  
  # Neovim基本設定
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    
    extraConfig = ''
      set number
      set relativenumber
      set expandtab
      set tabstop=2
      set shiftwidth=2
      set autoindent
      set smartindent
      syntax enable
    '';
  };
  
  # Direnv統合
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
EOF

log_success "Codespaces用Home Manager設定作成完了"

# 4. Dotfiles flake設定にCodespaces用設定追加
log_info "Dotfiles flake設定更新"
cd /workspaces/dotfiles

# 5. Claude CLI インストール (Node.js経由)
log_info "Claude CLI インストール"
npm install -g @anthropic-ai/claude-code
log_success "Claude CLI インストール完了"

# 6. シェル設定反映
log_info "シェル設定反映"
sudo chsh -s "$(which zsh)" vscode
log_success "デフォルトシェルをzshに変更"

# 7. 開発環境ヘルスチェック
log_info "開発環境ヘルスチェック"
echo "Nix version: $(nix --version)"
echo "Git version: $(git --version)"
echo "Node.js version: $(node --version)"
echo "Claude CLI: $(claude --version 2>/dev/null || echo 'Not available yet')"

log_success "🎉 GitHub Codespaces dotfiles環境セットアップ完了!"
echo ""
echo "🔧 次のステップ:"
echo "  1. ターミナルを再起動してzshを有効化"
echo "  2. 'dotfiles-rebuild' でHome Manager設定を適用"
echo "  3. 'gh auth login' でGitHub認証"
echo "  4. 'claude' でClaude Code起動"
echo ""