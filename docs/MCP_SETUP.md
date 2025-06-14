# 🤖 Claude Code MCP設定ガイド

> **Model Context Protocol (MCP)によるClaude Code機能拡張**

## 概要

MCPは、AIシステムとデータソース間の安全で双方向の接続を可能にするオープンスタンダードです。Claude Codeでは、MCPサーバーを通じて外部ツールやデータへの安全なアクセスが可能になります。

## 設定済みMCPサーバー

### 1. Filesystem Server 📁
**機能**: dotfilesディレクトリの安全なファイル操作
```bash
claude mcp add filesystem "npx @modelcontextprotocol/server-filesystem" "/Users/yuki/dotfiles"
```

**利点**:
- 設定ファイルの安全な読み書き
- ディレクトリ構造の把握
- ファイル内容の検索・分析
- 設定変更の自動化

### 2. Git Server 🌿
**機能**: Gitリポジトリの操作と管理
```bash
claude mcp add git "npx @modelcontextprotocol/server-git" "/Users/yuki/dotfiles"
```

**利点**:
- コミット履歴の確認
- 変更差分の分析
- ブランチ状態の監視
- バージョン管理支援

### 3. GitHub Server 🐙
**機能**: GitHub統合によるリポジトリ管理
```bash
claude mcp add github "npx @modelcontextprotocol/server-github"
```

**利点**:
- Issue・PR管理
- リポジトリ情報取得
- コラボレーション支援
- リモート操作

### 4. Brave Search Server 🔍
**機能**: Web検索とドキュメント検索
```bash
claude mcp add brave-search "npx @modelcontextprotocol/server-brave-search"
```

**利点**:
- 技術ドキュメント検索
- 設定例の検索
- トラブルシューティング
- ベストプラクティス調査

## 使用例

### ファイルシステム操作
```bash
claude -p "dotfilesディレクトリの構造を表示して"
claude -p "Neovim設定ファイルの内容を確認して"
claude -p "新しい設定ファイルを作成して"
```

### Git操作
```bash
claude -p "現在のGitステータスを確認して"
claude -p "最近のコミット履歴を表示して"
claude -p "変更されたファイルの差分を確認して"
```

### GitHub連携
```bash
claude -p "このリポジトリのIssueを確認して"
claude -p "プルリクエストの状況を教えて"
claude -p "リポジトリの統計情報を表示して"
```

### Web検索
```bash
claude -p "Neovimの最新プラグインについて検索して"
claude -p "LazyNvimの設定方法を調べて"
claude -p "macOSでの開発環境構築について検索して"
```

## 管理コマンド

### サーバー一覧確認
```bash
claude mcp list
```

### サーバー追加
```bash
claude mcp add <サーバー名> <コマンド> [引数...]
```

### サーバー削除
```bash
claude mcp remove <サーバー名>
```

### 設定確認
```bash
claude config list
```

## トラブルシューティング

### よくある問題

**Q: MCPサーバーが認識されない**
```bash
# Node.jsとnpmが最新か確認
node --version
npm --version

# MCPパッケージを再インストール
npm install -g @modelcontextprotocol/server-filesystem
```

**Q: ファイルアクセス権限エラー**
```bash
# ディレクトリの権限確認
ls -la /Users/yuki/dotfiles

# Claude Codeの権限設定確認
claude config list
```

**Q: GitHub連携でエラー**
```bash
# GitHub Personal Access Token設定
export GITHUB_PERSONAL_ACCESS_TOKEN="your_token_here"
```

## セキュリティ考慮事項

### アクセス制御
- Filesystemサーバーはdotfilesディレクトリのみアクセス可能
- Gitサーバーは読み取り専用操作を推奨
- GitHub tokenは環境変数で管理

### 監査ログ
- MCPサーバーの操作ログを定期的に確認
- 不審なアクセスパターンの監視
- 権限の定期的な見直し

## 今後の拡張予定

### 追加予定MCPサーバー
- **Postgres Server**: データベース操作
- **Docker Server**: コンテナ管理
- **Kubernetes Server**: クラスター管理
- **AWS Server**: クラウドリソース管理

### カスタムMCPサーバー
- dotfiles専用の設定管理サーバー
- プロジェクト固有のワークフロー自動化
- CI/CD統合サーバー

---

このMCP設定により、Claude Codeはdotfilesプロジェクトのコンテキストを深く理解し、より効果的な支援を提供できます。