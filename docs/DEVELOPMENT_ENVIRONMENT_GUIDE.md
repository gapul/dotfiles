# Development Environment Guide - Phase 4 Task 4.4

このガイドでは、Phase 4 Task 4.4で実装された高度な開発環境統合システムの使用方法を説明します。

## 🛠️ 開発環境統合システムの概要

### 4段階プロファイル

1. **minimal**: 最小限の開発環境
   - LSP: Nix, Bash, Markdown
   - プロジェクトタイプ: Node.js, Python
   - AI ツール: 無効

2. **standard**: 標準的な開発環境 (デフォルト)
   - LSP: TypeScript, HTML, CSS, JSON, Python, Nix, YAML, Markdown, Bash
   - プロジェクトタイプ: Node.js, Python, Rust, Go, React, Next.js, Docker
   - AI ツール: 無効

3. **full**: 完全な開発環境
   - LSP: 15言語サーバー対応
   - プロジェクトタイプ: 全タイプ対応
   - AI ツール: 無効

4. **ai-powered**: AI統合開発環境
   - 全機能 + AI開発ツール統合
   - GitHub Copilot, Claude, ChatGPT統合

## 🚀 セットアップ手順

### 1. 開発環境プロファイルの設定

プロファイルを変更するには、`nix/platforms/common/development/default.nix`を編集:

```nix
config.dotfiles.development = {
  enable = true;
  profile = "ai-powered";  # minimal/standard/full/ai-powered
};
```

### 2. 設定の適用

```bash
# Darwin (macOS) の場合
nix run nix-darwin -- switch --flake .#default

# または justfile を使用
just rebuild
```

### 3. 開発環境の確認

```bash
# 全体的なヘルスチェック
dev-health

# 各コンポーネントの確認
lsp-health       # LSP サーバー
ai-tools-health  # AI ツール (ai-powered プロファイルの場合)
project-health   # プロジェクト環境
```

## 📋 Language Server Protocol (LSP) 統合

### 対応言語

- **Web開発**: TypeScript, JavaScript, HTML, CSS, JSON
- **システム言語**: Rust, Go, C/C++
- **スクリプト言語**: Python, Bash, Lua
- **設定言語**: Nix, YAML, Markdown
- **データベース**: SQL

### Neovim での使用

LSPは自動的に設定されます:

```lua
-- 主要なキーバインディング (自動設定済み)
-- gd: 定義へジャンプ
-- K: ホバー情報表示
-- <leader>rn: リネーム
-- <leader>ca: コードアクション
-- <leader>f: フォーマット
```

### VS Code での使用

LSPサーバーのパスが自動設定され、推奨拡張機能も設定されます。

## 🤖 AI開発ツール統合 (ai-powered プロファイル)

### GitHub Copilot

```bash
# Copilot CLI の使用
copilot suggest -t shell "ファイルをリネームしたい"
copilot explain "git rebase -i HEAD~3"

# AI支援コミット
ai-commit  # 変更内容から適切なコミットメッセージを生成
```

### Claude Integration

MCP (Model Context Protocol) 対応:

```bash
# Claude 設定ファイル確認
cat ~/.config/claude/claude.json

# ファイルシステム MCP サーバーが設定済み
# GitHub MCP サーバーが設定済み
```

### Neovim AI統合

```lua
-- Copilot 設定 (自動適用済み)
-- <M-l>: 提案を受け入れ
-- <M-]>: 次の提案
-- <M-[>: 前の提案
-- <C-]>: 提案を拒否

-- ChatGPT 統合
-- :ChatGPT でチャット開始
```

## 🗂️ プロジェクト環境自動セットアップ

### 新プロジェクト作成

```bash
# 基本的な使用方法
project-init my-app react ./projects/

# 自動検出を使用
project-init my-app auto

# ショートカット (カレントディレクトリに作成)
mkproject my-app react
```

### 対応プロジェクトタイプ

- **Web**: nodejs, react, nextjs, vue, angular
- **システム**: rust, go, cpp
- **スクリプト**: python, php, ruby
- **モバイル**: flutter
- **インフラ**: docker, terraform, ansible

### プロジェクト構造

各プロジェクトには以下が自動生成されます:

```
my-project/
├── .envrc              # direnv 設定
├── shell.nix           # Nix 開発環境
├── .vscode/            # VS Code 設定
│   ├── settings.json
│   └── extensions.json
├── .gitignore          # プロジェクトタイプ別 gitignore
└── README.md           # プロジェクト説明
```

## 🐳 Development Containers

### Docker 統合

```bash
# Docker ステータス確認
docker system info

# 開発コンテナ用 Nix統合
devcontainer-nix .devcontainer/devcontainer.json
```

### VS Code Dev Containers

プロジェクト初期化時に`.devcontainer/devcontainer.json`が自動生成され、以下が含まれます:

- 言語固有の開発環境
- 必要な VS Code 拡張機能
- AI ツール統合

## ⚡ 開発ワークフロー

### 日常的な使用パターン

```bash
# 1. 新プロジェクト開始
mkproject awesome-app react

# 2. プロジェクトディレクトリに移動
cd awesome-app

# 3. 開発環境確認
devstatus

# 4. 開発開始
dev  # nix develop または direnv が自動実行

# 5. AI支援開発
ai-chat "Reactでカウンターコンポーネントを作りたい"
copilot suggest -t shell "ESLintでTypeScriptのルールを設定"

# 6. コミット
ai-commit  # AI生成のコミットメッセージ
```

### マルチプロジェクト管理

```bash
# プロジェクト間移動
proj-cd  # 現在のプロジェクトルートへ

# プロジェクトタイプ確認
proj-type

# 開発環境クリーンアップ
devclean  # Nix store, Docker, node_modules など
```

## 🔧 カスタマイズ

### LSP 設定のカスタマイズ

`nix/platforms/common/development/lsp/default.nix`で設定変更:

```nix
config.dotfiles.development.lsp = {
  enabledLanguages = [ "typescript" "python" "rust" ];
  globalConfig.formatting.format_on_save = true;
  nvimIntegration = true;
  vscodeIntegration = true;
};
```

### AI ツール設定

`nix/platforms/common/development/ai-tools/default.nix`で設定:

```nix
config.dotfiles.development.ai-tools = {
  copilotSupport = true;
  claudeSupport = true;
  mcpSupport = true;
};
```

### プロジェクト環境設定

`nix/platforms/common/development/project-env/default.nix`で設定:

```nix
config.dotfiles.development.project-env = {
  supportedTypes = [ "nodejs" "python" "rust" "docker" ];
  direnvIntegration = true;
  vscodeIntegration = true;
};
```

## 🩺 トラブルシューティング

### 一般的な問題と解決策

1. **LSP サーバーが起動しない**
   ```bash
   lsp-health  # 問題を特定
   lsp-restart  # サーバー再起動
   ```

2. **AI ツールが動作しない**
   ```bash
   ai-tools-health  # 環境変数と依存関係を確認
   ```

3. **プロジェクト環境が読み込まれない**
   ```bash
   project-health  # 設定ファイルをチェック
   direnv allow    # direnv を許可
   ```

4. **開発環境が重い**
   ```bash
   devclean  # 不要なファイルをクリーンアップ
   ```

### ログの確認

```bash
# Neovim LSP ログ
tail -f ~/.local/share/nvim/lsp.log

# direnv ログ
direnv status

# Docker ログ
docker system events
```

## 📚 参考リンク

- [Language Server Protocol](https://langserver.org/)
- [GitHub Copilot CLI](https://cli.github.com/manual/gh_copilot)
- [Model Context Protocol](https://modelcontextprotocol.io/)
- [Development Containers](https://containers.dev/)
- [direnv](https://direnv.net/)

## 🎯 次のステップ

1. プロファイルを`ai-powered`に設定してAI支援開発を体験
2. 新しいプロジェクトで`project-init`を使用
3. VS Code Dev Containersで一貫した開発環境を構築
4. MCP統合でClaude Codeとの連携を強化

このガイドは継続的に更新されます。新機能や改善点があれば、CLAUDE.mdも合わせて確認してください。