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

### 開発環境
```bash
# プロジェクト初期化
cd project-dir && direnv allow  # 環境変数設定

# 言語環境
nix develop                     # 開発シェル起動
nix run .#project-init          # プロジェクトテンプレート作成
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

## 🔧 トラブルシューティング

### よくある問題

**Q: 設定適用でエラーが発生**
```bash
nix flake check                 # 設定検証
nix eval .#platformInfo --json  # プラットフォーム確認
```

**Q: パッケージが見つからない**
```bash
nix search nixpkgs <package>    # パッケージ検索
```

## 📚 関連ドキュメント

- [README.md](README.md) - 基本セットアップとクイックスタート
- [SECURITY.md](SECURITY.md) - セキュリティ関連設定
- [docs/](docs/) - 詳細ガイド

### 🚀 Phase 5: Modern CLI Integration

- [PHASE5_IMPLEMENTATION_COMPLETE.md](PHASE5_IMPLEMENTATION_COMPLETE.md) - 実装完了レポート
- [QUICK_START_MODERN_CLI.md](QUICK_START_MODERN_CLI.md) - クイックスタートガイド
- [TROUBLESHOOTING_PHASE5.md](TROUBLESHOOTING_PHASE5.md) - トラブルシューティング
- [POST_INSTALLATION_CHECK.sh](POST_INSTALLATION_CHECK.sh) - 動作確認スクリプト

## 📈 最新の成果

### 2025年7月11日 - Phase 5 Modern CLI Integration 完了 ✅

**実装済み機能:**
- Modern CLI Tools統合 (eza, bat, ripgrep, fd, zoxide, lazygit, yazi, bottom)
- エイリアス統一管理システム
- Neovim TUIツール統合
- エイリアス競合問題の完全解決
- 3-10倍高速なファイル・テキスト検索
- 学習型スマートナビゲーション

**クイックスタート:**
```bash
# 新機能をすぐに体験
exec zsh && ./POST_INSTALLATION_CHECK.sh
ls -la && cat README.md && rg "nix" && z dotfiles
```

---

*最終更新: 2025年7月11日*