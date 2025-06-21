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

---

*最終更新: 2025年6月21日*