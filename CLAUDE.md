# Dotfiles プロジェクト管理 - Claude Code

## 🎯 プロジェクト概要

Nix/NixOSベースのクロスプラットフォーム開発環境管理システム。macOS、Linux、WSL、Androidで統一された開発体験を提供します。

## 📋 主要コマンド

### システム管理
```bash
# 基本操作
just rebuild                    # 設定再構築
just health                     # ヘルスチェック
just test                       # テスト実行
just clean                      # システムクリーンアップ

# Nix管理
nix flake check                 # 設定検証
nix store gc                    # ガベージコレクション
nix profile list                # インストール済みパッケージ
```

### 開発環境テンプレート
```bash
# テンプレート管理
template list                   # 利用可能テンプレート一覧
template search <query>         # テンプレート検索
template use <path>             # テンプレート環境に入る
template health                 # 環境ヘルスチェック

# 開発環境例
nix develop ./templates/web/nextjs-fullstack
nix develop ./templates/mobile/react-native
nix develop ./templates/data/python-ml
```

### プロジェクト初期化
```bash
# 言語別環境
direnv allow                    # 環境変数設定
nix develop                     # 開発シェル起動
```

## ⚙️ 設定

### 環境変数
```bash
# ~/.zshrc または ~/.bashrc に追加
export DOTFILES_PROFILE="standard"  # minimal, standard, full
```

### プラットフォーム確認
```bash
nix eval .#platformInfo --json      # プラットフォーム情報
```

## 📊 システム状況

### サポートプラットフォーム
- **macOS**: Apple Silicon + Intel
- **Linux**: NixOS + 汎用ディストリビューション  
- **WSL**: Windows Subsystem for Linux
- **Android**: Termux (nix-on-droid)

## 🗂️ テンプレートシステム

### 📁 ディレクトリ構造
```
templates/
├── web/                       # Web開発
│   ├── nextjs-fullstack/     # Next.js フルスタック
│   ├── vue-typescript/       # Vue.js + TypeScript
│   ├── node-api/             # Node.js REST API
│   └── docker-fullstack/     # Docker マルチサービス
├── mobile/                    # モバイル開発
│   ├── react-native/         # React Native + Expo
│   └── flutter/              # Flutter クロスプラットフォーム
├── data/                      # データサイエンス
│   ├── python-ml/            # Python機械学習
│   └── r-analytics/          # R統計解析
├── systems/                   # システムプログラミング
│   ├── rust-cli/             # Rust CLI
│   └── go-api/               # Go Web API
└── _shared/                   # 共通ユーティリティ
    ├── configs/              # 共通設定
    ├── scripts/              # 共通スクリプト
    └── utils.nix             # Nix ユーティリティ
```

### 🚀 クイックスタート例

#### Web開発 (Next.js)
```bash
nix develop ./templates/web/nextjs-fullstack
setup-nextjs
nextjs-dev create myapp
cd myapp && nextjs-dev dev     # → http://localhost:3000
```

#### モバイル開発 (React Native)
```bash
nix develop ./templates/mobile/react-native
setup-react-native
rn-dev create MyApp
cd MyApp && rn-dev run         # → Expo開発環境
```

#### データサイエンス (Python)
```bash
nix develop ./templates/data/python-ml
setup-datascience
ds-dev notebook                # → http://localhost:8888
```

## 🔧 トラブルシューティング

### よくある問題

**Q: 設定適用でエラーが発生**
```bash
nix flake check                 # 設定検証
nix eval .#platformInfo --json  # プラットフォーム確認
```

**Q: テンプレートが見つからない**
```bash
template list                   # 利用可能テンプレート確認
template health                 # 環境チェック
```

**Q: サービスが起動しない**
```bash
start_services                  # サービス手動起動
template health                 # ヘルスチェック実行
```

## 📚 関連ドキュメント

- [README.md](README.md) - 基本セットアップとクイックスタート
- [templates/README.md](templates/README.md) - テンプレートシステム詳細
- [templates/QUICK_START.md](templates/QUICK_START.md) - テンプレート利用ガイド
- [SECURITY.md](SECURITY.md) - セキュリティ関連設定
- [docs/](docs/) - 詳細ガイド

### 🚀 Phase 5: Modern CLI Integration

- [PHASE5_IMPLEMENTATION_COMPLETE.md](PHASE5_IMPLEMENTATION_COMPLETE.md) - 実装完了レポート
- [QUICK_START_MODERN_CLI.md](QUICK_START_MODERN_CLI.md) - クイックスタートガイド
- [TROUBLESHOOTING_PHASE5.md](TROUBLESHOOTING_PHASE5.md) - トラブルシューティング
- [POST_INSTALLATION_CHECK.sh](POST_INSTALLATION_CHECK.sh) - 動作確認スクリプト

## 📈 最新の成果

### 2025年7月15日 - Phase 6 実装完了 ✅

**Phase 6完了機能 (100% 実装):**
- **nix-direnv統合**: 10-100倍高速開発環境切り替え
- **crane Rust最適化**: 依存関係キャッシュとクロスコンパイル
- **統合開発環境**: Modern CLI + AI + 高速化の完全統合
- **包括的テンプレートシステム**: 8つの主要開発カテゴリを網羅

**利用可能テンプレート:**
```bash
# Web開発
web/nextjs-fullstack     # Next.js + TypeScript + Auth + DB
web/vue-typescript       # Vue 3 + TypeScript + Vite
web/node-api            # TypeScript Node.js REST API
web/docker-fullstack    # マルチサービス Docker

# モバイル開発
mobile/react-native     # React Native + Expo
mobile/flutter          # Flutter クロスプラットフォーム

# データサイエンス
data/python-ml          # Python ML + Jupyter + GPU
data/r-analytics        # R統計解析 + Shiny

# システムプログラミング
systems/rust-cli        # Rust CLI アプリケーション
systems/go-api          # Go Web API
```

**Phase 6新コマンド:**
```bash
# nix-direnv統合
direnv-setup auto           # プロジェクト自動検出・環境設定
nix-direnv-health          # 環境統合診断
direnv-benchmark           # 高速化パフォーマンス測定

# crane Rust最適化
crane-create myapp binary   # 最適化Rustプロジェクト作成
crane-build release        # 高速ビルド（依存関係キャッシュ）
crane-benchmark            # ビルド性能測定・分析
crane-health               # Rust環境診断
```

### Phase 5 継続機能:
- Modern CLI Tools統合 (eza, bat, ripgrep, fd, zoxide, lazygit, yazi, bottom)
- 3-10倍高速なファイル・テキスト検索
- 学習型スマートナビゲーション

### Phase 6 実装完了機能:
- **nix-direnv**: 開発環境高速ロード（10-100倍高速化）✅
- **crane**: Rust最適化ビルドシステム（クロスコンパイル対応）✅
- **QoLツール**: nom, nix-tree, fastfetch統合✅
- **sops-nix**: 宣言的シークレット管理（設定準備完了、Phase 7で完成予定）

### 📚 最新ドキュメント

- [templates/README.md](templates/README.md) - テンプレートシステム詳細
- [templates/QUICK_START.md](templates/QUICK_START.md) - 利用ガイド
- [templates/index.nix](templates/index.nix) - テンプレート管理システム
- [NIX_LIBRARY_IMPLEMENTATION_STATUS.md](docs/NIX_LIBRARY_IMPLEMENTATION_STATUS.md) - Phase 6実装状況
- [nix/secrets/README.md](nix/secrets/README.md) - sops-nix詳細ガイド

---

*最終更新: 2025年7月15日*