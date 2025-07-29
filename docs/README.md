# Dotfiles Documentation

**最終更新:** 2025年7月12日  
**バージョン:** Phase 6 完了版

## 📚 ドキュメント構成

### 🚀 クイックスタート
- プロジェクト概要は [../README.md](../README.md) を参照
- テンプレートクイックスタートは [../templates/QUICK_START.md](../templates/QUICK_START.md) を参照

### 🎯 フェーズ別ドキュメント

#### Phase 6: NIX_LIBRARY統合 (完了)
- [Phase 6 完了レポート](PHASE6_COMPLETION_REPORT.md) - NIX_LIBRARY統合の完了報告と実装詳細

### 🔧 開発ガイド
- [自動化システムガイド](guides/automation.md) - Infrastructure as Code & CI/CDの活用
- [Web開発環境ガイド](guides/web-development.md) - モダンWeb開発環境
- [Neovim設定](guides/neovim.md) - Neovim設定の詳細
- [WezTerm設定](guides/wezterm.md) - WezTerm設定の詳細
- [QMK/VIA統合ガイド](todo/qmk-via-keyboard-integration.md) - カスタムキーボード統合

### 📋 今後の実装予定
- [TODOタスク一覧](todo/) - 今後の実装予定タスクの詳細

## 🎯 現在のシステム状態

### ✅ 完了済みフェーズ
- **Phase 4**: マルチプラットフォーム対応 & CI/CD統合
- **Phase 5**: Modern CLI Integration (eza, bat, ripgrep, fd, zoxide, lazygit, yazi, bottom)
- **Phase 6-A**: Script Nix統合 & ワークフロー自動化

### 🔄 有効な機能
```bash
# システム管理
health                    # 統一ヘルスチェック
rebuild                   # システム再構築
cleanup                   # システムクリーンアップ

# 開発環境
project-type             # プロジェクト自動検出
ci-optimize              # CI/CD最適化
security-setup           # セキュリティ自動設定

# Modern CLIツール
ls → eza                 # カラフルなファイル一覧
cat → bat                # シンタックスハイライト
grep → rg                # 高速テキスト検索
find → fd                # 直感的ファイル検索
cd → z                   # スマートディレクトリ移動
```

## 🛠️ 技術スタック

### プラットフォーム
- **メイン**: macOS (Apple Silicon + Intel)
- **サポート**: Linux, WSL, Android (Termux)

### パッケージ管理
- **Nix**: システムパッケージ & 環境管理
- **Home Manager**: ユーザー設定管理
- **Homebrew**: macOS補完パッケージ

### 開発環境
- **ターミナル**: WezTerm + Zsh + Starship
- **エディター**: Neovim (メイン), VSCode, Zed
- **Git UI**: LazyGit + Enhanced TUI統合
- **AI統合**: Ollama + shell-gpt + mods

### セキュリティ
- **暗号化**: SOPS + Age
- **SSH**: Ed25519 + セキュリティ強化設定
- **GPG**: セキュリティ強化設定
- **権限管理**: 自動監査 & 修正

## 📖 使い方

### 新規セットアップ
```bash
# リポジトリクローン
git clone https://github.com/your-username/dotfiles.git
cd dotfiles

# セットアップガイドに従って実行
cat docs/user/setup-guide.md
```

### 日常的な使用
```bash
# システム状態確認
health

# 設定更新
rebuild

# プロジェクト開発開始
cd new-project
project-type              # プロジェクト種別自動検出
setup-project             # 環境自動セットアップ
```

### トラブルシューティング
```bash
# 詳細診断
health --verbose

# 特定機能の確認
security-verify           # セキュリティ状態
ci-analyze                # CI/CD状態
```

## 🎯 用途別ナビゲーション

### 🆕 **初めて使用する方**
1. [プロジェクト概要](../README.md) - 最初に読む
2. [テンプレートクイックスタート](../templates/QUICK_START.md) - 環境構築詳細
3. [Phase 6 完了レポート](PHASE6_COMPLETION_REPORT.md) - システム全体の理解

### 🔧 **既存ユーザー（日常使用）**
1. [テンプレートシステム](../templates/README.md) - 開発環境テンプレート活用
2. [自動化システムガイド](guides/automation.md) - Infrastructure as Code活用
3. [Web開発環境ガイド](guides/web-development.md) - Web開発環境

### 💻 **開発者**
1. [Web開発環境ガイド](guides/web-development.md) - Web開発環境
2. [Neovim設定](guides/neovim.md) - エディター設定
3. [QMK/VIA統合ガイド](todo/qmk-via-keyboard-integration.md) - カスタムキーボード

### 🏗️ **システム管理者**
1. [Phase 6 完了レポート](PHASE6_COMPLETION_REPORT.md) - システム設計
2. [自動化システムガイド](guides/automation.md) - Infrastructure as Code
3. [TODOタスク一覧](todo/) - 今後の実装予定

## 🔗 関連リンク

- [メインREADME](../README.md) - プロジェクト概要
- [CLAUDE.md](../CLAUDE.md) - プロジェクト管理情報
- [テンプレートシステム](../templates/README.md) - 開発環境テンプレート

## 📊 ドキュメント統計

### 整理後の構成
```
Phase 6 完了版: 体系化されたドキュメント
- Phase 6 完了レポート (統合版)
- 開発ガイド (4個)
- TODOタスク (3個)
- 削減率: 不要ファイル削除により大幅簡素化
```

### ドキュメント品質向上
- **一元化**: Phase 6 完了レポートに統合
- **最新化**: 実装完了項目を反映
- **保守性**: 重複排除と統合
- **アクセシビリティ**: 階層的構造

---

**🎯 このドキュメント構成により、dotfilesシステムの全体像から詳細まで体系的にアクセスできます。**