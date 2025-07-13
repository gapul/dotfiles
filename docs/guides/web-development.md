# 🌐 Web開発環境ガイド

**最終更新:** 2025年7月12日  
**対象:** Phase 6 統合版

## 📋 概要

Nixベースのdotfiles環境に統合されたモダンWeb開発環境のセットアップと使用方法について説明します。

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
- 全機能有効
- Tauri対応
- パフォーマンス最適化
- 高度な開発ツール

## 🚀 セットアップ

### 環境設定
```bash
# Web開発環境の有効化
# nix/common/default.nix で設定
dotfiles.development.web.enable = true;
dotfiles.development.web.profile = "standard";

# 設定適用
just rebuild
```

### プロジェクト作成
```bash
# プロジェクトタイプ自動検出
project-type

# 新しいプロジェクト作成
setup-project
```

## 📖 使用方法

### 基本操作
```bash
# プロジェクト環境確認
project-type
project-info

# 開発サーバー起動（フレームワーク自動検出）
npm run dev    # または
yarn dev       # または  
bun dev        # または
pnpm dev
```

### Tauri開発
```bash
# Tauriプロジェクト初期化
cargo tauri init

# 開発モード
cargo tauri dev

# ビルド
cargo tauri build
```

## 🔧 設定

### TypeScript設定
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true
  }
}
```

### Vite設定
```javascript
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 3000,
    open: true
  }
})
```

## 🆘 トラブルシューティング

### よくある問題

#### パッケージマネージャーが見つからない
```bash
# パッケージマネージャー確認
which npm && echo "npm available"
which bun && echo "bun available"

# 環境再読み込み
exec zsh
```

#### プロジェクトタイプが認識されない
```bash
# 手動でプロジェクトファイル確認
ls package.json tsconfig.json

# プロジェクト情報詳細表示
project-info
```

### ログ確認
```bash
# 開発環境ヘルスチェック
health

# Web開発関連のログ
ls ~/.cache/nix/logs/
```

## 🔗 関連リンク

- [プロジェクト検出ガイド](../DEVELOPMENT_ENVIRONMENT_GUIDE.md)
- [Tauri公式ドキュメント](https://tauri.app/v1/guides/)
- [Vite公式ドキュメント](https://vitejs.dev/)

---

*このガイドは現在のdotfiles Phase 6統合版に基づいています。*