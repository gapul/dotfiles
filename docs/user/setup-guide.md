# 🚀 セットアップガイド

> **マルチプラットフォーム対応システムの完全セットアップ手順**

## 🎯 セットアップオプション

### 🆕 クイックスタート（推奨）
最小限の手順で基本環境を構築

### 🔧 フルセットアップ
全機能を有効にした企業環境対応セットアップ

### 🔄 移行セットアップ
既存環境からの段階的移行

---

## 🆕 クイックスタート

### 前提条件
```bash
# 1. Nix インストール確認
nix --version || curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# 2. リポジトリクローン
git clone https://github.com/gapul/dotfiles.git ~/.config/dotfiles
cd ~/.config/dotfiles
```

### プラットフォーム別セットアップ

#### macOS (nix-darwin)
```bash
# 1. プラットフォーム検出
nix run .#detect-platform

# 2. システム適用
nix run nix-darwin -- switch --flake .#default

# 3. 確認
darwin-rebuild --version
which eza bat fd
```

#### Linux/WSL (home-manager)
```bash
# 1. Home Manager適用
home-manager switch --flake .#$USER@linux

# 2. 確認  
home-manager generations
which starship tmux
```

#### Android (nix-on-droid)
```bash
# 1. Termux環境セットアップ
nix-on-droid switch --flake .#android

# 2. 確認
which git gh jq
```

---

## 🔧 フルセットアップ

### Phase 1: 基盤構築
```bash
# 1. Nix環境準備
cd ~/.config/dotfiles/nix/platforms
nix flake check --impure

# 2. プロファイル設定
export DOTFILES_DEV_PROFILE="ai-powered"
export DOTFILES_AUTO_PROFILE="enterprise"

# 3. システム適用
## macOS
nix run nix-darwin -- switch --flake .#default

## Linux
home-manager switch --flake .#$USER@linux
```

### Phase 2: セキュリティ設定
```bash
# 1. SOPS-nix初期化
age-keygen -o ~/.config/sops/age/keys.txt

# 2. シークレット設定
cp nix/platforms/security/sops/secrets.yaml.example secrets.yaml
sops secrets.yaml

# 3. SOPS暗号化テスト
sops --version
```

### Phase 3: 開発環境
```bash
# 1. 開発環境確認
dev-health

# 2. AI プラットフォーム設定
ai-platform-health

# 3. LSP 確認
lsp-health
```

### Phase 4: 自動化・運用
```bash
# 1. 自動化システム確認
auto-health

# 2. 監視スタック初期化
monitoring-init prometheus

# 3. クラウド設定
cloud-check-status
```

---

## 🔄 移行セットアップ

### 既存Homebrew環境からの移行

#### Step 1: 現状分析
```bash
# 現在のパッケージ確認
brew list --formula > homebrew_packages.txt
brew list --cask > homebrew_casks.txt

# 依存関係確認
brew deps --tree --installed > homebrew_deps.txt
```

#### Step 2: 段階的移行
```bash
# Phase 1: CLIツール移行（2週間）
nix run nix-darwin -- switch --flake .#default

# Phase 2: 開発環境移行（2週間）
export DOTFILES_DEV_PROFILE="standard"
darwin-rebuild switch --flake .

# Phase 3: GUI アプリ移行（1週間）
# Homebrew cask → Nix 段階的移行

# Phase 4: クリーンアップ（1週間）
brew uninstall --ignore-dependencies <package>
```

#### Step 3: 検証・調整
```bash
# 移行確認
which git gh docker
eza --version
bat --version

# 設定調整
nvim ~/.config/dotfiles/nix/platforms/flake.nix
darwin-rebuild switch --flake ~/.config/dotfiles
```

---

## 🔧 カスタマイズ設定

### 個人設定の追加
```bash
# 1. 個人情報設定ファイル作成
cp .gitconfig.example .gitconfig
cp ssh/config.example ssh/config

# 2. 個人情報編集
nvim .gitconfig  # name, email設定
nvim ssh/config  # サーバー情報設定

# 3. シンボリックリンク作成
ln -sf ~/.config/dotfiles/.gitconfig ~/.gitconfig
ln -sf ~/.config/dotfiles/ssh/config ~/.ssh/config
```

### プロファイル選択
```bash
# 開発環境プロファイル
## minimal - 基本ツールのみ
## standard - 完全開発環境  
## full - AI統合・高度ツール
## ai-powered - Claude MCP・GitHub Copilot統合
export DOTFILES_DEV_PROFILE="ai-powered"

# 自動化プロファイル
## minimal - 基本IaC
## standard - Kubernetes・CI/CD
## full - マルチクラウド・監視
## enterprise - 完全運用・セキュリティ
export DOTFILES_AUTO_PROFILE="enterprise"

# 設定適用
just rebuild
```

---

## 🆘 トラブルシューティング

### よくある問題

#### Nix インストール失敗
```bash
# 既存Nix削除
sudo rm -rf /nix
sudo rm /etc/synthetic.conf

# 再インストール
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

#### システム適用エラー
```bash
# 設定検証
cd nix/platforms && nix flake check --impure

# 詳細ログ
darwin-rebuild switch --flake . --show-trace

# ロールバック
darwin-rebuild --rollback
```

#### 権限エラー
```bash
# Nix daemon確認
sudo launchctl list | grep nix

# 権限修正
sudo chown -R $USER /nix/var/nix/profiles/per-user/$USER
```

### 診断コマンド
```bash
# システム状況確認
nix doctor
darwin-rebuild --version
home-manager --version

# プラットフォーム情報
nix eval .#platformInfo --json

# ヘルスチェック
dev-health
auto-health
monitoring-dashboard status
```

---

## 📊 セットアップ完了確認

### 基本環境チェック
```bash
# 必須コマンド確認
which git gh jq yq eza bat fd zoxide
starship --version
tmux -V

# プロンプト確認
echo $STARSHIP_CONFIG
echo $SHELL
```

### 開発環境チェック
```bash
# 言語環境
python3 --version
node --version
go version
rustc --version

# エディター
nvim --version
code --version
```

### 自動化環境チェック
```bash
# インフラツール
terraform version
kubectl version --client
helm version --client

# クラウドツール
aws --version
gcloud version
az version

# 監視ツール
prometheus --version
grafana-server --version
```

---

## 🚀 次のステップ

### 日常運用開始
```bash
# 設定更新
just rebuild

# ヘルスチェック
just health

# システム監視
monitoring-dashboard status
```

### 高度な機能活用
- [開発環境ガイド](DEVELOPMENT_ENVIRONMENT_GUIDE.md)
- [AI システム詳細](../CLAUDE.md)
- [セキュリティガイド](../SECURITY.md)

---

*このガイドで環境構築に関する疑問が解決しない場合は、[Issues](https://github.com/gapul/dotfiles/issues)で質問してください。*