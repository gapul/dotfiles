# 🏠 個人用 Dotfiles

Nix/NixOSベースのクロスプラットフォーム開発環境。macOS、Linux、WSL、Androidで統一された開発体験を提供します。

## 📚 ドキュメント

詳細なドキュメントは [`docs/`](docs/) ディレクトリを参照してください。

- [📚 ドキュメント構造](docs/README.md) - 全体概要
- [🚀 セットアップガイド](docs/guides/setup.md) - 基本インストール
- [🛠️ 開発環境ガイド](docs/guides/development-environment.md) - 開発ツール設定
- [🔧 Nix設定リファレンス](docs/reference/nix-configuration.md) - 詳細設定
- [🌐 プラットフォーム対応](docs/reference/platform-support.md) - マルチプラットフォーム情報
- [🔧 トラブルシューティング](docs/reference/troubleshooting.md) - 問題解決

## ✨ 特徴

- **宣言的設定管理** - Nixによる再現可能な環境構築
- **マルチプラットフォーム対応** - 4つのプラットフォームで動作
- **開発ツール統合** - エディター、シェル、ターミナルの統一設定
- **プロジェクト環境自動化** - direnvとNixによる自動環境切り替え

## 📁 プロジェクト構造

```
dotfiles/
├── flake.nix                      # メインFlake設定（プロジェクトルート）
├── flake.lock                     # Nix依存関係ロック
├── justfile                       # タスクランナー設定
├── nix/                           # Nix設定ファイル
│   ├── common/                    # 共通モジュール
│   │   ├── platform-detection.nix # プラットフォーム検出
│   │   ├── packages/              # パッケージ管理
│   │   └── themes/                # テーマ設定
│   ├── darwin/                    # macOS設定（nix-darwin）
│   ├── linux/                     # Linux設定（home-manager）
│   ├── wsl/                       # WSL設定
│   ├── android/                   # Android設定（nix-on-droid）
│   └── security/                  # SOPS暗号化設定
├── configs/                       # アプリケーション設定
│   ├── editors/nvim/              # Neovim設定
│   ├── terminal/                  # ターミナル設定
│   └── wm/                        # ウィンドウマネージャー設定
├── docs/                          # ドキュメント
├── scripts/                       # ユーティリティスクリプト
├── docs/                          # ドキュメント
│   ├── guides/                    # セットアップガイド
│   ├── reference/                 # APIリファレンス
│   └── tutorials/                 # チュートリアル
└── .github/                       # CI/CD設定
    └── workflows/                 # GitHub Actions
```

## 🎯 サポートプラットフォーム

- **macOS** - nix-darwin、Homebrew統合
- **Linux** - NixOS、汎用ディストリビューション
- **WSL** - Windows Subsystem for Linux
- **Android** - Termux + nix-on-droid

## 🚀 クイックスタート

> 詳細なセットアップ手順は [セットアップガイド](docs/guides/setup.md) を参照してください。

### 自動インストール（推奨）

```bash
# Nixをインストール
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# dotfilesをクローン
git clone https://github.com/gapul/dotfiles.git ~/.config/dotfiles
cd ~/.config/dotfiles

# プラットフォーム別セットアップ
# macOS
sudo nix run nix-darwin -- switch --flake .#default

# Linux/WSL
home-manager switch --flake .#$USER@$(uname | tr '[:upper:]' '[:lower:]')
```

### メインインストール

```bash
# リポジトリクローン
git clone https://github.com/YOUR_USERNAME/dotfiles.git ~/.config/dotfiles
cd ~/.config/dotfiles

# プラットフォーム別セットアップ

# macOS
nix run nix-darwin -- switch --flake .#default

# Linux
home-manager switch --flake .#$USER@linux

# WSL
home-manager switch --flake .#$USER@wsl

# Android (Termux)
nix-on-droid switch --flake .#android
```

## 🛠️ 基本コマンド

### 設定管理
```bash
# 設定再構築
just rebuild

# ヘルスチェック
just health

# システムクリーンアップ
just clean

# Nixガベージコレクション
nix store gc
```

### 開発環境
```bash
# プロジェクト初期化
cd project-dir
direnv allow  # 環境変数自動設定

# 開発シェル起動
nix develop

# プロジェクトテンプレート作成
nix run .#project-init
```

## ⚙️ 設定カスタマイズ

### 環境変数設定
```bash
# ~/.zshrc または ~/.bashrc に追加
export DOTFILES_PROFILE="standard"  # minimal, standard, full
```

### テーマ変更
カラーテーマは `nix/common/themes/colors.nix` で設定可能です。

## 🔧 主要ツール

### エディター
- **Neovim** - メインエディター、LSP統合
- **VS Code** - GUI開発環境
- **Zed** - 高速エディター

### ターミナル
- **WezTerm** - GPU加速ターミナル
- **Starship** - クロスシェルプロンプト
- **Zsh** - インタラクティブシェル

### 開発ツール
- **Git** - バージョン管理
- **Docker** - コンテナ化
- **direnv** - 環境変数管理

## 📚 ドキュメント

- [CLAUDE.md](CLAUDE.md) - プロジェクト詳細情報
- [SECURITY.md](SECURITY.md) - セキュリティ設定
- [docs/](docs/) - 詳細ガイド

## 🤝 コントリビューション

1. リポジトリをフォーク
2. フィーチャーブランチ作成
3. 変更をコミット
4. プルリクエスト作成

## 📄 ライセンス

MIT License

## 🔧 トラブルシューティング

**設定エラーが発生した場合:**
```bash
nix flake check                 # 設定検証
nix eval .#platformInfo --json  # プラットフォーム確認
```

**パッケージが見つからない場合:**
```bash
nix search nixpkgs <package>    # パッケージ検索
```

---

*最終更新: 2025年6月21日*