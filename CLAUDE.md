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

## 🔄 開発ワークフロー

### Phase実装手順
Phase実装時は以下の順序で進行：

1. **ブランチ作成** - `git checkout -b feature/phaseX-taskY`
2. **仕様書確認** - `docs/PHASEX_TASK_Y_SPECIFICATION.md`の詳細レビュー  
3. **現在のdotfiles確認** - 既存構造・設定・依存関係の把握
4. **実装** - Nixモジュール・スクリプト・設定ファイルの作成/更新
5. **テスト** - 機能テスト・統合テスト・パフォーマンステスト実施
6. **修正** - テスト結果に基づく不具合修正・最適化
7. **完成** - 最終動作確認・ドキュメント更新
8. **プルリクエスト** - `gh pr create`でレビュー・マージ

### コマンド例
```bash
# Phase 3.1 開始例
git checkout -b feature/phase3-task1-project-detection
cd /Users/yuki/dotfiles
just test && just health  # 現状確認
# 実装...
just rebuild && just test  # テスト
gh pr create --title "feat: Phase 3.1 - プロジェクト種別検出システム" --body "詳細説明..."
```

---

*最終更新: 2025年7月2日*