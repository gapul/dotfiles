# nix移行 クイックスタートガイド

> **すぐに始められるnix移行手順**

## 🚀 Phase 1: 即座実行可能な手順

### Step 1: nixインストール

```bash
# Determinateシステム版nix（推奨）
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# インストール確認
nix --version
which nix
```

### Step 2: flakes有効化確認

```bash
# flakes機能確認
nix flake --help

# 設定確認
cat ~/.config/nix/nix.conf
```

### Step 3: nix設定ディレクトリ準備

```bash
# 設定ディレクトリ作成
mkdir -p ~/.config/nix-darwin

# dotfilesからnix設定をコピー
cp -r ~/dotfiles/nix/* ~/.config/nix-darwin/

# flake.lockを初期化
cd ~/.config/nix-darwin
nix flake update
```

### Step 4: nix-darwinセットアップ

```bash
# nix-darwinインストール
nix run nix-darwin -- switch --flake ~/.config/nix-darwin

# システム確認
darwin-rebuild --version
```

### Step 5: 基本設定テスト

```bash
# 設定適用テスト
darwin-rebuild switch --flake ~/.config/nix-darwin

# 基本コマンド確認
which git
which gh
which jq
```

## 📋 移行チェックリスト

### ✅ Phase 1完了確認

- [ ] nix正常インストール
- [ ] nix-darwin動作確認
- [ ] 基本CLIツール利用可能
- [ ] 既存dotfiles連携確認
- [ ] flake設定更新可能

### 🔧 トラブルシューティング

#### nixインストール失敗
```bash
# 既存nix削除（必要時）
sudo rm -rf /nix
sudo rm /etc/synthetic.conf

# 再インストール
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

#### darwin-rebuild失敗
```bash
# 設定ファイル構文確認
nix flake check ~/.config/nix-darwin

# 詳細ログで実行
darwin-rebuild switch --flake ~/.config/nix-darwin --show-trace
```

#### Homebrew衝突
```bash
# 一時的にHomebrew PATHを除外
export PATH="/nix/var/nix/profiles/default/bin:$PATH"

# または特定パッケージのみnixを優先
export PATH="/run/current-system/sw/bin:$PATH"
```

## 🎯 次のステップ

### Phase 2準備
```bash
# 開発環境テスト
cd ~/projects/some-project
nix develop

# Python環境テスト
nix develop ~/.config/nix-darwin#python

# Node.js環境テスト  
nix develop ~/.config/nix-darwin#node
```

### 設定カスタマイズ
```bash
# flake.nix編集
nvim ~/.config/nix-darwin/flake.nix

# 設定適用
darwin-rebuild switch --flake ~/.config/nix-darwin
```

### Homebrew併用管理
```bash
# 現在のHomebrew状況確認
brew list --formula > homebrew_before.txt
brew list --cask > homebrew_casks_before.txt

# 段階的移行の準備
brew deps --tree --installed > homebrew_deps.txt
```

## 📚 参考コマンド

### 日常運用
```bash
# システム更新
darwin-rebuild switch --flake ~/.config/nix-darwin

# ユーザー環境更新
home-manager switch --flake ~/.config/nix-darwin

# flake更新
nix flake update ~/.config/nix-darwin

# ガベージコレクション
nix store gc
nix store optimise
```

### 開発環境
```bash
# プロジェクト別環境
echo 'use flake' > .envrc
direnv allow

# 一時的な環境
nix shell nixpkgs#python312
nix shell nixpkgs#nodejs_20
```

### トラブルシューティング
```bash
# ログ確認
journalctl -u nix-daemon

# 設定検証
nix flake check ~/.config/nix-darwin

# 設定ロールバック
darwin-rebuild --rollback
```

これらの手順に従って、段階的にnix環境へ移行できます。