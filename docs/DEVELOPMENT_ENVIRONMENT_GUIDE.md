# 🛠️ 開発環境ガイド

> **Phase 4.4 AI統合開発環境の完全活用ガイド**

## 🎯 概要

Phase 4.4で実装された開発環境統合システムは、Language Server Protocol (LSP)、コンテナ、AI開発ツールを統合した次世代開発環境です。

## 🏗️ プロファイルシステム

### プロファイル一覧
- **minimal**: 基本ツール・軽量設定
- **standard**: 完全開発環境・LSP統合（デフォルト）
- **full**: AI統合・高度な開発ツール
- **ai-powered**: Claude MCP・GitHub Copilot完全統合

### プロファイル設定
```bash
# プロファイル変更
export DOTFILES_DEV_PROFILE="ai-powered"
just rebuild

# 現在のプロファイル確認
echo $DOTFILES_DEV_PROFILE
```

---

## 🚀 基本操作

### 開発環境確認
```bash
# 開発環境全体のヘルスチェック
dev-health

# 各コンポーネント個別確認
lsp-health          # Language Server状況
ai-tools-health     # AI開発ツール状況
containers-health   # コンテナ環境状況
```

---

## 🧠 Language Server Protocol (LSP)

### サポート言語（fullプロファイル）
- **Web**: TypeScript, JavaScript, HTML, CSS, JSON
- **Systems**: Rust, Go, C/C++, Nix
- **Scripting**: Python, Bash, Lua
- **Data**: YAML, TOML, Markdown
- **Infrastructure**: Terraform, Docker

### LSP管理
```bash
# LSP状況確認
lsp-health

# 言語別LSP確認
lsp-status typescript
lsp-status rust
lsp-status python

# LSP再起動
lsp-restart typescript
lsp-restart all
```

### エディター統合

#### Neovim
```bash
# LSP設定確認
nvim +checkhealth lsp

# キーバインド
# gd: 定義へ移動
# gr: 参照検索  
# K: ドキュメント表示
# <leader>ca: コードアクション
```

#### VSCode
```bash
# 設定確認
code --list-extensions | grep -E "(typescript|rust|python)"

# 自動補完・診断が有効化
```

---

## 🤖 AI開発ツール統合

### GitHub Copilot（ai-poweredプロファイル）

#### CLI統合
```bash
# コマンド提案
gh copilot suggest "deploy to kubernetes"

# コード説明
gh copilot explain "docker run -d -p 80:80 nginx"

# 設定確認
gh copilot status
```

#### エディター統合
```bash
# Neovim: GitHub Copilot有効確認
nvim +checkhealth copilot

# VSCode: Copilot拡張確認
code --list-extensions | grep copilot
```

### Claude MCP Protocol（ai-poweredプロファイル）

#### ファイルシステム統合
```bash
# MCP サーバー状況確認
ai-tools-health

# Claude Code でファイル操作・検索が自動化
```

#### GitHub統合
```bash
# GitHub MCP確認
gh auth status

# PR・Issue管理がClaude経由で自動化
```

---

## 📦 コンテナ開発環境

### Development Containers

#### プロジェクト環境管理
```bash
# 利用可能な開発コンテナ確認
dev-containers list

# プロジェクト別環境起動
dev-containers start my-project
dev-containers stop my-project

# 環境削除
dev-containers remove old-project
```

#### VS Code Dev Containers
```bash
# devcontainer設定確認
cat .devcontainer/devcontainer.json

# Remote-Containers拡張で起動
code .  # Dev Container: Reopen in Container
```

### Docker/Podman統合
```bash
# コンテナランタイム確認
containers-health

# Docker状況
docker ps --format "table {{.Names}}\t{{.Status}}"

# Podman状況（Linux）
podman ps --format "table {{.Names}}\t{{.Status}}"
```

---

## 🎨 プロジェクト環境管理

### 自動環境切り替え（direnv）

#### プロジェクト設定
```bash
# プロジェクトディレクトリで環境設定
echo 'use flake' > .envrc
direnv allow

# 自動でプロジェクト固有の開発環境が有効化
```

#### Nix開発シェル
```bash
# プロジェクト別シェル定義
echo '{
  inputs = { nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable"; };
  outputs = { nixpkgs, ... }: {
    devShells.default = nixpkgs.legacyPackages.x86_64-linux.mkShell {
      buildInputs = with nixpkgs.legacyPackages.x86_64-linux; [
        nodejs_20 python312 rustc cargo
      ];
    };
  };
}' > flake.nix

# 開発環境起動
nix develop
```

### プロジェクトテンプレート
```bash
# React プロジェクト
project-init react my-app
cd my-app && npm start

# Python API
project-init fastapi my-api
cd my-api && python main.py

# Rust CLI
project-init rust-cli my-tool
cd my-tool && cargo run
```

---

## ⚙️ カスタマイズ設定

### LSP設定カスタマイズ
```bash
# カスタム言語サーバー追加
nvim nix/platforms/common/development/lsp/default.nix

# 設定例: Svelte サポート追加
# svelte = { package = pkgs.nodePackages.svelte-language-server; };
```

### AI ツール設定
```bash
# GitHub Copilot設定
gh config set copilot.enabled true

# Claude MCP設定確認
cat ~/.claude/mcp_config.json
```

### コンテナ設定
```bash
# Docker Compose設定テンプレート
project-init docker-compose my-stack

# Kubernetes開発環境
project-init k8s-dev my-microservice
```

---

## 🔧 統合ワークフロー

### 典型的な開発フロー

#### 1. プロジェクト開始
```bash
# 開発環境確認
dev-health

# プロジェクト作成
project-init react my-web-app
cd my-web-app

# 自動環境切り替え
echo 'use flake' > .envrc
direnv allow
```

#### 2. 開発作業
```bash
# エディターで開発（AI支援付き）
nvim src/App.tsx    # GitHub Copilot補完
code .              # VS Code with Copilot

# LSP機能活用
# - 自動補完・診断
# - 定義ジャンプ・参照検索
# - コードアクション・リファクタリング
```

#### 3. テスト・デバッグ
```bash
# 開発コンテナでテスト
dev-containers start test-env
npm test

# Docker環境でのテスト
docker-compose up -d
curl http://localhost:3000/api/health
```

#### 4. デプロイ準備
```bash
# Claude MCPでCI/CD設定生成
# GitHub Actions workflow自動生成

# コンテナイメージビルド
docker build -t my-app:latest .
```

---

## 📊 監視・メトリクス

### 開発環境監視
```bash
# 開発ツール使用状況
dev-metrics

# LSP パフォーマンス
lsp-metrics

# AI ツール統計
ai-tools-metrics

# コンテナリソース使用量
containers-metrics
```

---

## 🆘 トラブルシューティング

### よくある問題

#### LSPが起動しない
```bash
# LSP状況確認
lsp-health

# 言語サーバー再起動
lsp-restart typescript

# Neovim LSP診断
nvim +checkhealth lsp
```

#### GitHub Copilot が動作しない
```bash
# 認証確認
gh auth status

# Copilot状況
gh copilot status

# 再認証
gh auth refresh
```

#### 開発コンテナエラー
```bash
# Docker状況確認
docker system info

# 開発コンテナ再構築
dev-containers rebuild my-project

# VS Code Dev Container診断
code --list-extensions | grep container
```

### 診断コマンド
```bash
# 開発環境全体診断
dev-health

# 詳細診断
dev-health --verbose

# 特定コンポーネント診断
lsp-health --check-all
ai-tools-health --detailed
containers-health --system-info
```

---

## 📚 参考リソース

### 設定ファイル
- **LSP設定**: `nix/platforms/common/development/lsp/`
- **AI統合**: `nix/platforms/common/development/ai-tools/`
- **コンテナ**: `nix/platforms/common/development/containers/`

### 外部ドキュメント
- [LSP Specification](https://microsoft.github.io/language-server-protocol/)
- [GitHub Copilot Documentation](https://docs.github.com/en/copilot)
- [VS Code Dev Containers](https://code.visualstudio.com/docs/devcontainers/containers)

### 関連ガイド
- [自動化システムガイド](AUTOMATION_GUIDE.md)
- [AI システム詳細](../CLAUDE.md)
- [セキュリティガイド](../SECURITY.md)

---

*このガイドで開発環境の活用に関する疑問が解決しない場合は、[Issues](https://github.com/gapul/dotfiles/issues)で質問してください。*