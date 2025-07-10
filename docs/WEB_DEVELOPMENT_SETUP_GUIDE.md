# 🌐 Web開発環境セットアップガイド

## 📋 概要

このガイドでは、Nixベースのdotfiles環境に統合されたモダンWeb開発環境のセットアップと使用方法について説明します。

## ✨ 主要機能

### 🏗️ 技術スタック
- **ランタイム**: Node.js 22, Bun 1.1+, Deno 2.0
- **パッケージマネージャー**: npm, pnpm, yarn, bun (自動検出)
- **ビルドツール**: Vite, Turbopack, SWC, esbuild
- **フレームワーク**: React (Next.js), Vue, Svelte, Astro
- **デスクトップ**: Tauri (Rust + WebView)
- **開発ツール**: ESLint, Prettier, TypeScript

### 🎯 プロファイル

#### Minimal
- 基本的なランタイムとツール
- React + Vite
- TypeScript無効

#### Standard（デフォルト）
- 主要なランタイムとツール
- React + Next.js
- TypeScript有効
- ESLint + Prettier

#### Full
- 全ランタイムとフレームワーク
- Tauri デスクトップアプリ対応
- 高度なビルド最適化

#### Performance
- 最大パフォーマンス設定
- Turbopack使用
- 積極的な最適化

## 🚀 セットアップ

### 1. Web開発環境の有効化

既存のdotfiles設定で、`standard`以上のプロファイルを使用している場合、Web開発環境は自動的に有効になります。

```bash
# 現在の設定確認
nix eval .#darwinConfigurations.default.config.dotfiles.development.profile

# 手動で有効化する場合（flake.nixで設定）
dotfiles.development.profile = "standard";  # または "full", "ai-powered"
```

### 2. 設定の適用

```bash
# macOSの場合
nix run nix-darwin -- switch --flake .

# Linuxの場合
home-manager switch --flake .
```

### 3. 動作確認

```bash
# Web開発環境の健康チェック
web-env-health

# 開発環境全体のチェック
dev-health
```

## 🛠️ 使用方法

### プロジェクト初期化

```bash
# React プロジェクト（Vite）
web-init my-app react

# Next.js プロジェクト
web-init my-app nextjs --typescript

# Tauri デスクトップアプリ
tauri-init my-desktop-app react
```

### 開発サーバー

```bash
# プロジェクトディレクトリで
web-dev

# または
dev
npm run dev
```

### ビルドとデプロイ

```bash
# プロダクションビルド
web-build

# Tauriアプリのビルド
tauri-build

# バンドルサイズ分析
npm run analyze
```

### パッケージ管理

```bash
# 自動検出パッケージマネージャー
pm install          # 適切なPMを自動選択
pm add react        # 依存関係追加
pm run build        # スクリプト実行

# 特定のパッケージマネージャー
bun install         # Bun使用
pnpm install        # pnpm使用
npm install         # npm使用
```

### テストとLint

```bash
# テスト実行
web-test
npm test

# コード品質チェック
web-lint
npm run lint

# コード整形
format
npm run lint:fix
```

## 📁 プロジェクト構造例

### React + Vite プロジェクト
```
my-react-app/
├── src/
│   ├── components/
│   ├── lib/
│   ├── styles/
│   └── App.tsx
├── public/
├── vite.config.ts
├── tsconfig.json
├── package.json
└── .eslintrc.json
```

### Next.js プロジェクト
```
my-nextjs-app/
├── src/
│   ├── app/              # App Router
│   │   ├── layout.tsx
│   │   └── page.tsx
│   ├── components/
│   └── lib/
├── public/
├── next.config.js
├── tsconfig.json
└── package.json
```

### Tauri プロジェクト
```
my-tauri-app/
├── src/                  # フロントエンド
│   ├── components/
│   └── App.tsx
├── src-tauri/           # バックエンド
│   ├── src/
│   │   └── main.rs
│   ├── Cargo.toml
│   └── tauri.conf.json
├── vite.config.ts
└── package.json
```

## ⚙️ 設定カスタマイズ

### Web開発環境の詳細設定

```nix
# flake.nixまたは設定ファイルで
web = {
  enable = true;
  profile = "standard";  # minimal, standard, full, performance
  
  features = {
    core = true;         # コアツール
    frameworks = true;   # フレームワーク
    desktop = false;     # Tauri デスクトップ
    tooling = true;      # 開発ツール
  };
  
  frameworks = {
    primary = "react";
    enabled = [ "react" ];
    typescript = true;
    testing = "vitest";
    bundler = "vite";
  };
  
  desktop = {
    profile = "standard";  # basic, standard, advanced, production
  };
};
```

### フレームワーク個別設定

```nix
web.frameworks.react = {
  version = "18";
  frameworks = [ "nextjs" "vite" ];
  typescript = true;
  styling = "tailwind";
};

web.frameworks.react.nextjs = {
  version = "15";
  router = "app";
  turbopack.enable = true;
  features = {
    serverComponents = true;
    typescript = true;
    tailwindcss = true;
  };
};
```

### Tauri設定

```nix
web.desktop.tauri = {
  rustToolchain.version = "stable";
  features = {
    bundleFormats = [ "deb" "appimage" "dmg" "app" ];
    autoUpdater = true;
    systemTray = true;
  };
  
  security = {
    securityLevel = "standard";  # minimal, standard, strict, paranoid
    allowlist = {
      fs = [ "read" "readDir" "exists" ];
      shell = [ "open" ];
      window = [ "close" "hide" "show" "maximize" "minimize" ];
    };
  };
};
```

## 🔧 便利なコマンド

### ヘルスチェック
```bash
web-env-health           # Web環境全体
web-health              # Web コアツール
react-health            # React環境
nextjs-health           # Next.js環境
tauri-health            # Tauri環境
frameworks-health       # フレームワーク全体
```

### プロジェクト管理
```bash
# プロジェクト作成
react-init my-app vite --typescript
nextjs-init my-app --turbo --tailwind
tauri-init my-desktop-app react

# 開発ワークフロー
web-workflow init my-app --framework react --typescript
web-workflow dev
web-workflow build --desktop
web-workflow test
web-workflow deploy
```

### セキュリティとメンテナンス
```bash
# Tauriセキュリティ監査
tauri-security-audit

# 依存関係チェック
deps-check
deps-update
deps-unused

# バンドル分析
analyze
bundle-size
```

## 🐛 トラブルシューティング

### よくある問題

#### 1. パッケージマネージャーの競合
```bash
# ロックファイルを確認
detect-pm

# 特定のPMを強制使用
bun install  # または pnpm install, npm install
```

#### 2. TypeScript エラー
```bash
# 型チェック
npm run type-check

# TypeScript再起動（VS Code）
# Cmd+Shift+P -> "TypeScript: Restart TS Server"
```

#### 3. Tauri ビルドエラー
```bash
# Rust環境確認
tauri-health

# 依存関係更新
cargo update
```

#### 4. Next.js Turbopack問題
```bash
# Turbopack無効化
npm run dev  # turbopackなし

# 設定確認
nextjs-health
```

### ログとデバッグ

```bash
# デバッグモードでサーバー起動
DEBUG=* npm run dev

# Rust デバッグ情報
RUST_LOG=debug tauri-dev

# ビルド詳細情報
npm run build --verbose
```

## 📚 参考リンク

- [Next.js Documentation](https://nextjs.org/docs)
- [Tauri Documentation](https://tauri.app/guides/)
- [Vite Documentation](https://vitejs.dev/guide/)
- [Bun Documentation](https://bun.sh/docs)

## 🔄 更新履歴

- **2025-07-10**: Web開発環境 Phase 1 実装完了
  - React/Next.js/Tauri 統合
  - パッケージマネージャー自動検出
  - プロファイルベース設定
  - 包括的ヘルスチェック