# Dotfiles Documentation

**最終更新:** 2025年7月12日  
**バージョン:** Phase 6 完了版

## 📚 ドキュメント構成

### 🚀 クイックスタート
- [セットアップガイド](user/setup-guide.md) - 初回インストールと基本設定
- [トラブルシューティング](guides/TROUBLESHOOTING_PHASE5.md) - よくある問題と解決方法

### 🎯 フェーズ別ドキュメント

#### Phase 5: Modern CLI Integration (完了)
- [Modern CLI 完全ガイド](PHASE5_MODERN_CLI_COMPLETE_GUIDE.md) - Modern CLIツール統合の包括的ガイド

#### Phase 6: Advanced Integration & Automation (進行中)
- [Phase 6 Nix Library 完了計画](todo/phase6-nix-library-completion.md) - 残りのNixライブラリ統合
- [Script Nix統合レポート](../PHASE6_SCRIPT_NIX_INTEGRATION_COMPLETE.md) - スクリプトNix統合の完了報告

### 🔧 開発ガイド
- [開発環境ガイド](DEVELOPMENT_ENVIRONMENT_GUIDE.md) - 開発環境の詳細設定
- [自動化システムガイド](guides/automation.md) - Infrastructure as Code & CI/CDの活用
- [Web開発環境ガイド](guides/web-development.md) - モダンWeb開発環境
- [Neovim設定](guides/neovim.md) - Neovim設定の詳細
- [WezTerm設定](guides/wezterm.md) - WezTerm設定の詳細
- [QMK/VIA統合ガイド](todo/qmk-via-keyboard-integration.md) - カスタムキーボード統合

### 📊 実装レポート
- [システム実装レポート](reports/) - 各フェーズの実装詳細
  - [Phase 4 システム最適化](reports/PHASE4_SYSTEM_OPTIMIZATION_SUMMARY.md)
  - [ファイル整理レポート](reports/DOTFILES_CLEANUP_REPORT.md)
  - [CI/CD最適化レポート](reports/ci-cd-optimization-report.md)
  - [セキュリティ設定レポート](reports/security-baseline-setup-report.md)

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
1. [セットアップガイド](user/setup-guide.md) - 最初に読む
2. [開発環境ガイド](DEVELOPMENT_ENVIRONMENT_GUIDE.md) - 環境構築詳細
3. [トラブルシューティング](guides/TROUBLESHOOTING_PHASE5.md) - 問題解決

### 🔧 **既存ユーザー（日常使用）**
1. [Modern CLI 完全ガイド](PHASE5_MODERN_CLI_COMPLETE_GUIDE.md) - Modern CLIツール活用
2. [自動化システムガイド](guides/automation.md) - Infrastructure as Code活用
3. [トラブルシューティング](guides/TROUBLESHOOTING_PHASE5.md) - 問題解決

### 💻 **開発者**
1. [Web開発環境ガイド](guides/web-development.md) - Web開発環境
2. [Neovim設定](guides/neovim.md) - エディター設定
3. [QMK/VIA統合ガイド](todo/qmk-via-keyboard-integration.md) - カスタムキーボード

### 🏗️ **システム管理者**
1. [Phase 6 Nix Library完了計画](todo/phase6-nix-library-completion.md) - システム設計
2. [自動化システムガイド](guides/automation.md) - Infrastructure as Code
3. [実装レポート](reports/) - 詳細な技術情報

## 🔗 関連リンク

- [メインREADME](../README.md) - プロジェクト概要
- [CLAUDE.md](../CLAUDE.md) - プロジェクト管理情報
- [Phase 5 実装完了](../PHASE5_IMPLEMENTATION_COMPLETE.md)
- [Phase 6 スクリプト統合完了](../PHASE6_SCRIPT_NIX_INTEGRATION_COMPLETE.md)

## 📊 ドキュメント統計

### 整理前後の比較
```
整理前: 30+ 散在ドキュメント
整理後: 15個 体系化ドキュメント
削減率: 50%

重複削除: 8個のPhase 5関連ドキュメント → 1個に統合
アーカイブ整理: 不要なlegacy/slides削除
構造最適化: 4層の明確な階層構造
```

### ドキュメント品質向上
- **ナビゲーション**: 用途別ガイド追加
- **検索性**: カテゴリ別整理
- **保守性**: 重複排除と統合
- **アクセシビリティ**: 階層的構造

---

**🎯 このドキュメント構成により、dotfilesシステムの全体像から詳細まで体系的にアクセスできます。**