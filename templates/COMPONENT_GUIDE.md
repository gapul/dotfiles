# Component Development Guide

テンプレートをポータブルなコンポーネントとして活用する包括的ガイド

## 🧩 コンポーネントシステム概要

各開発テンプレートを独立したコンポーネントとして扱い、自由に組み合わせ可能な開発環境を提供します。

### 📦 コンポーネントの特徴

- **ポータビリティ**: どこでも動く独立したコンポーネント
- **組み合わせ可能**: 複数コンポーネントの自動統合
- **依存関係管理**: 自動的な依存関係解決
- **環境分離**: コンポーネント間の環境競合回避

## 🚀 クイックスタート

### 1. 単一コンポーネント作成

```bash
# フロントエンドコンポーネント
component-dev create frontend my-app ./frontend
cd frontend && component-dev start

# バックエンドコンポーネント  
component-dev create backend api-server ./backend
cd backend && component-dev start

# モバイルコンポーネント
component-dev create mobile mobile-app ./mobile
cd mobile && component-dev start
```

### 2. マルチコンポーネント構成

```bash
# フルスタックプロジェクト
mkdir fullstack-project && cd fullstack-project

# フロントエンド
component-dev create frontend web-ui ./frontend

# バックエンド
component-dev create backend api ./backend

# データベース
component-dev create database main-db ./database

# 全体起動
multi-dev start
```

## 📋 利用可能コンポーネント

### 🎨 Frontend Components
```bash
# Next.js React フロントエンド
component-dev create frontend my-web-ui ./frontend

# 提供機能: web-ui, frontend-routes
# 依存関係: web-api
# ポート: 3000
```

### ⚙️ Backend Components
```bash
# Node.js REST API
component-dev create backend my-api ./backend

# 提供機能: web-api, rest-endpoints
# 依存関係: database
# ポート: 8000
```

### 📱 Mobile Components
```bash
# React Native モバイルアプリ
component-dev create mobile my-mobile-app ./mobile

# 提供機能: mobile-app
# 依存関係: web-api
# ポート: 8081 (Expo)
```

### 🗄️ Data Components
```bash
# PostgreSQL データベース
component-dev create database main-db ./database

# 提供機能: database, postgresql
# 依存関係: なし
# ポート: 5432

# Redis キャッシュ
component-dev create cache redis-cache ./cache

# 提供機能: cache, redis
# 依存関係: なし
# ポート: 6379
```

### 🧬 ML Components
```bash
# Python 機械学習環境
component-dev create ml ml-models ./ml

# 提供機能: ml-models, jupyter
# 依存関係: なし
# ポート: 8888 (Jupyter), 5000 (MLflow)
```

## 🏗️ プロジェクト構成例

### フルスタックWebアプリケーション

```bash
mkdir ecommerce-app && cd ecommerce-app

# フロントエンド (Next.js)
component-dev create frontend storefront ./frontend

# バックエンド (Node.js API)
component-dev create backend api ./backend

# データベース (PostgreSQL)
component-dev create database main-db ./database

# キャッシュ (Redis)
component-dev create cache session-cache ./cache

# 全体起動
multi-dev quick fullstack ecommerce-app
```

### モバイル + バックエンド

```bash
mkdir chat-app && cd chat-app

# モバイルアプリ (React Native)
component-dev create mobile chat-mobile ./mobile

# バックエンド (Node.js API)
component-dev create backend chat-api ./backend

# データベース
component-dev create database chat-db ./database

# 全体起動
multi-dev quick mobile chat-app
```

### MLプラットフォーム

```bash
mkdir ai-platform && cd ai-platform

# ML開発環境 (Python)
component-dev create ml model-training ./ml

# Webダッシュボード (Next.js)
component-dev create frontend dashboard ./dashboard

# API (Node.js)
component-dev create backend ml-api ./backend

# データベース
component-dev create database ml-db ./database

# 全体起動
multi-dev quick ml ai-platform
```

## 🔧 コンポーネント管理

### コンポーネント情報確認

```bash
# 利用可能コンポーネント一覧
component-dev list

# コンポーネント詳細情報
component info nextjs-frontend
component info node-api

# 現在のコンポーネント状態
cd my-component && component-dev status
```

### コンポーネント操作

```bash
# コンポーネント開始
cd my-component && component-dev start

# コンポーネント停止
component-dev stop

# コンポーネント環境に入る
component-dev enter

# 依存関係チェック
component-dev status
```

## 🎛️ 高度な使用方法

### 1. カスタムコンポーネント

```bash
# カスタムコンポーネント設定
cat > component.json << EOF
{
  "name": "custom-service",
  "type": "custom",
  "provides": ["custom-api"],
  "requires": ["database"],
  "ports": {"api": 9000},
  "environment": {
    "CUSTOM_ENV": "production"
  }
}
EOF
```

### 2. コンポーネント組み合わせ

```bash
# 事前定義された組み合わせ
nix develop -f templates/_shared/component.nix webStack
nix develop -f templates/_shared/component.nix mobileStack
nix develop -f templates/_shared/component.nix mlStack

# カスタム組み合わせ
component compose my-stack frontend backend database cache
```

### 3. 開発セッション管理

```bash
# マルチターミナルセッション開始
dev-session

# ワークスペース管理
workspace create fullstack-web myproject
workspace enter
workspace status
```

## 🔍 トラブルシューティング

### よくある問題

**Q: コンポーネントが起動しない**
```bash
# ヘルスチェック実行
component-dev status

# 依存関係確認
component info <component-name>

# サービス状態確認
multi-dev services start
```

**Q: ポート競合が発生**
```bash
# ポート使用状況確認
netstat -tulpn | grep LISTEN
lsof -i :3000

# 代替ポート設定
export PORT=3001
component-dev start
```

**Q: 依存関係エラー**
```bash
# 必要サービス起動
multi-dev services start

# 依存関係の手動起動
component-dev create database temp-db ./temp-db
cd temp-db && component-dev start
```

## 💡 ベストプラクティス

### 1. プロジェクト構造

```
my-project/
├── frontend/           # フロントエンドコンポーネント
│   ├── component.json
│   └── ...
├── backend/            # バックエンドコンポーネント
│   ├── component.json
│   └── ...
├── database/           # データベースコンポーネント
│   ├── component.json
│   └── .postgres/
└── project.json        # プロジェクト設定
```

### 2. 環境変数管理

```bash
# コンポーネント別環境変数
echo "API_URL=http://localhost:8000" > frontend/.env.local
echo "DATABASE_URL=postgresql://..." > backend/.env

# グローバル環境設定
export GLOBAL_CONFIG=production
```

### 3. 開発ワークフロー

```bash
# 1. プロジェクト初期化
multi-dev quick fullstack myproject

# 2. 開発セッション開始
cd myproject && multi-dev start

# 3. コンポーネント別開発
cd frontend && component-dev enter
cd backend && component-dev enter

# 4. 統合テスト
multi-dev status
```

## 🔗 統合機能

### GitHub Actions統合

```yaml
# .github/workflows/components.yml
name: Component Tests

on: [push, pull_request]

jobs:
  test-components:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v22
      
      - name: Test Frontend Component
        run: |
          cd frontend
          nix develop --command component-dev start &
          # テスト実行
      
      - name: Test Backend Component  
        run: |
          cd backend
          nix develop --command component-dev start &
          # テスト実行
```

### Docker統合

```bash
# コンポーネントのDocker化
component-dev docker build frontend
component-dev docker build backend

# Docker Compose生成
multi-dev docker compose
```

## 📚 参考資料

- [Templates README](README.md) - 基本テンプレートシステム
- [Quick Start Guide](QUICK_START.md) - クイックスタートガイド
- [Workspace Management](_shared/workspace.nix) - ワークスペース管理
- [Component System](_shared/component.nix) - コンポーネントシステム

---

🎯 **目標**: 任意の技術スタックを数分で組み立て可能な、ポータブルで再利用可能な開発コンポーネントシステム