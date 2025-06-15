# Browser MCP Server セットアップガイド

> **Claude Codeでのブラウザ自動化・Web操作機能**

## 🎯 概要

Browser MCPサーバーにより、Claude Codeで以下のブラウザ操作が可能になります：

- **ページナビゲーション**: URLアクセス・リンククリック
- **要素操作**: ボタンクリック・フォーム入力
- **データ抽出**: テキスト・画像・PDFの取得
- **スクリーンショット**: ページの視覚的確認
- **JavaScript実行**: 動的コンテンツの操作

## 🔧 利用可能なMCPサーバー

### 1️⃣ Playwright MCP Server（推奨）
```json
"playwright": {
  "command": "npx",
  "args": ["@executeautomation/playwright-mcp-server"],
  "description": "Browser automation and web scraping using Playwright"
}
```

**特徴:**
- クロスブラウザ対応（Chrome、Firefox、Safari）
- 高品質スクリーンショット
- ネットワーク監視
- モバイル端末シミュレーション

### 2️⃣ Puppeteer MCP Server
```json
"puppeteer": {
  "command": "npx", 
  "args": ["@modelcontextprotocol/server-puppeteer"],
  "description": "Browser automation using Puppeteer"
}
```

**特徴:**
- Headless Chrome制御
- PDF生成
- パフォーマンス分析
- 軽量・高速

## 📦 インストール手順

### Step 1: 必要パッケージのインストール

```bash
# Playwright MCP Server
npm install -g @executeautomation/playwright-mcp-server

# Puppeteer MCP Server
npm install -g @modelcontextprotocol/server-puppeteer

# Playwrightブラウザのインストール（初回のみ）
npx playwright install
```

### Step 2: MCP設定の適用

```bash
# dotfilesの設定を適用
./install.sh

# MCPサーバー追加
claude mcp add playwright "npx @executeautomation/playwright-mcp-server"
claude mcp add puppeteer "npx @modelcontextprotocol/server-puppeteer"
```

### Step 3: 動作確認

```bash
# MCPサーバー一覧確認
claude mcp list

# 設定ファイル確認
cat ~/Library/Application\ Support/Claude/claude_desktop_config.json
```

## 🚀 使用例

### 基本的なページアクセス

**目的**: Webページにアクセスして情報を取得

```
Claude Codeに以下を依頼:
"https://github.com/modelcontextprotocol/servers にアクセスして、
README内容を取得してください"
```

**実行される操作:**
1. ブラウザでページにアクセス
2. ページコンテンツを読み取り
3. 構造化された情報として返答

### フォーム入力・操作

**目的**: Webフォームの自動入力

```
Claude Codeに以下を依頼:
"GitHubの検索フォームでnix-darwinを検索して、
上位5つのリポジトリ情報を取得してください"
```

**実行される操作:**
1. GitHub検索ページにアクセス
2. 検索フォームに「nix-darwin」を入力
3. 検索実行
4. 結果の取得・整理

### スクリーンショット取得

**目的**: ページの視覚的確認

```
Claude Codeに以下を依頼:
"現在のdotfilesプロジェクトのGitHubページのスクリーンショットを
取得してください"
```

### データ抽出・分析

**目的**: 構造化データの抽出

```
Claude Codeに以下を依頼:
"nixpkgs公式サイトから、yabaiパッケージの対応状況を
調査してください"
```

## 🔧 高度な使用例

### 1️⃣ 技術情報収集
```
"Stack Overflowでnix-darwinの最新トラブルシューティング情報を
収集して、よくある問題と解決方法をまとめてください"
```

### 2️⃣ プロジェクト調査
```
"GitHub Trendsで今週人気のdotfilesリポジトリを調査して、
参考になる設定や新しいツールがないか確認してください"
```

### 3️⃣ ドキュメント生成
```
"Homebrewの公式サイトから、brewコマンドの使用方法を取得して、
nix移行時の対応表を作成してください"
```

### 4️⃣ 設定比較
```
"人気のdotfilesリポジトリから、tmux設定の共通パターンを
調査して、現在の設定との比較分析をしてください"
```

## ⚠️ 使用時の注意事項

### セキュリティ
- **認証が必要なサイト**: 個人情報入力は避ける
- **プライベートページ**: アクセス権限を確認
- **API制限**: 過度なアクセスを避ける

### パフォーマンス
- **重いページ**: 読み込み時間を考慮
- **大量データ**: 適切な範囲で制限
- **同時実行**: 複数タブの同時操作は控える

### エラー対応
```bash
# MCPサーバー再起動
claude mcp restart playwright

# 設定確認
claude mcp status

# ログ確認
claude mcp logs playwright
```

## 🎯 実用的なワークフロー例

### dotfiles改善ワークフロー
1. **情報収集**: GitHub/Stack Overflowで最新ツール調査
2. **設定比較**: 人気リポジトリとの設定比較
3. **ドキュメント確認**: 公式ドキュメントでの機能確認
4. **実装・テスト**: 新機能の実装と動作確認

### nix移行サポート
1. **パッケージ対応調査**: nixpkgsでの対応状況確認
2. **設定例収集**: nix-darwinの実用設定例収集
3. **トラブルシューティング**: 既知問題の解決方法調査
4. **最新情報**: nix/home-manager最新動向の確認

Browser MCPにより、Claude Codeの能力が大幅に拡張され、より効率的なdotfiles管理と開発支援が可能になります。