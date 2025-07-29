# 🏠 個人用 Dotfiles

Nix/NixOSベースのクロスプラットフォーム開発環境。macOS、Linux、WSL、Androidで統一された開発体験を提供します。

## ✨ 特徴

- **宣言的設定管理** - Nixによる再現可能な環境構築
- **マルチプラットフォーム対応** - 4つのプラットフォームで動作
- **Modern CLI統合** - 3-10倍高速なファイル・テキスト検索
- **AI支援開発** - GitHub Copilotとエディター統合
- **開発ツール統合** - エディター、シェル、ターミナルの統一設定
- **プロジェクト環境自動化** - nix-direnvによる10-100倍高速環境切り替え
- **Rust最適化ビルド** - craneによる依存関係キャッシュとクロスコンパイル
- **Modern Academic Writing** - LuaLaTeX + BibLaTeX + SyncTeX統合TeX環境

## 📁 プロジェクト構造

```
dotfiles/
├── nix/                           # Nix設定ファイル
│   ├── flake.nix                  # メインFlake設定
│   ├── common/                    # 共通モジュール
│   ├── darwin/                    # macOS設定
│   ├── linux/                     # Linux設定  
│   ├── wsl/                       # WSL設定
│   └── android/                   # Android設定
├── configs/                       # アプリケーション設定
│   ├── editors/nvim/              # Neovim設定
│   ├── terminal/                  # ターミナル設定
│   └── wm/                        # ウィンドウマネージャー設定
├── docs/                          # ドキュメント
└── scripts/                       # ユーティリティスクリプト
```

## 🎯 サポートプラットフォーム

- **macOS** - nix-darwin、Homebrew統合
- **Linux** - NixOS、汎用ディストリビューション
- **WSL** - Windows Subsystem for Linux
- **Android** - Termux + nix-on-droid

## 🚀 セットアップ

### 前提条件

```bash
# Nixインストール
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

### インストール

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
# 高速環境自動切り替え (nix-direnv)
cd project-dir && direnv allow    # 自動環境検出・設定

# Rust最適化開発 (crane)
crane-create myapp binary         # 最適化済みRustプロジェクト作成
crane-build release              # 高速ビルド（依存関係キャッシュ）
crane-benchmark                  # パフォーマンス測定

# TeX/LaTeX環境 (有効化が必要)
# nix/flake.nix で dotfiles.development.tex.enable = true;
tex-health                       # TeX環境チェック
md2tex paper.md                 # Markdown→LaTeX変換
latex-build                      # LaTeX連続ビルド

# 開発環境管理
direnv-setup auto                # プロジェクト自動検出・設定
nix-direnv-health               # 環境診断
```

### Modern CLI体験
```bash
# 新機能をすぐに体験
exec zsh && ./POST_INSTALLATION_CHECK.sh
ls -la && cat README.md && rg "nix" && z dotfiles
```

### PDF処理
```bash
# PDF情報取得・基本操作
pdfinfo document.pdf                    # PDF情報表示
pdftotext document.pdf output.txt       # テキスト抽出

# パスワード保護解除
qpdf --decrypt --password=PASSWORD input.pdf output.pdf

# PDF結合・分割
pdftk file1.pdf file2.pdf cat output merged.pdf
pdftk input.pdf cat 1-3 output pages1-3.pdf

# PDF圧縮 (Ghostscript)
gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=/ebook \
   -dNOPAUSE -dQUIET -dBATCH -sOutputFile=compressed.pdf input.pdf
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
- **Neovim** - メインエディター、LSP統合、AI支援
- **VS Code** - GUI開発環境
- **Zed** - 高速エディター

### ターミナル
- **WezTerm** - GPU加速ターミナル
- **Starship** - クロスシェルプロンプト
- **Zsh** - インタラクティブシェル

### 🚀 Modern CLI Tools (Phase 5 完了)
- **eza** - ls代替（3倍高速ファイル表示）
- **bat** - cat代替（シンタックスハイライト付きページャー）
- **ripgrep** - grep代替（10倍高速テキスト検索）
- **fd** - find代替（8倍高速ファイル検索）
- **zoxide** - cd代替（学習型スマートナビゲーション）
- **lazygit** - Git TUIクライアント
- **yazi** - モダンファイルマネージャー
- **bottom** - top代替（システムモニター）

### 📄 PDF処理ツール
- **QPDF** - PDF処理・操作・暗号化解除
- **Poppler Utils** - PDF情報取得・変換（pdfinfo, pdftotext, pdfimages等）
- **Ghostscript** - PostScript/PDF処理エンジン・圧縮
- **PDFtk** - PDFマージ・分割・操作ツール

### 📝 TeX/LaTeX環境 (Modern Academic Writing)
- **TeXLive Medium** - 包括的なLaTeX distribution
- **LuaLaTeX** - Unicode対応、日本語フォント統合
- **BibLaTeX + Biber** - モダンな文献管理システム
- **VS Code + LaTeX Workshop** - GUI統合開発環境
- **Neovim + Vimtex** - ターミナル内LaTeX編集
- **Pandoc** - Markdown↔LaTeX変換
- **Zathura** - SyncTeX対応PDFビューアー
- **texlab LSP** - 言語サーバー統合
- **Noto CJK Fonts** - 日本語フォント自動設定

#### TeX推奨ワークフロー
```bash
# 1. 環境ヘルスチェック
tex-health

# 2. Markdown執筆 (Obsidian)
# paper.md を作成

# 3. LaTeX変換
md2tex paper.md                    # 基本変換
md2tex -b refs.bib -j paper.md     # 文献+日本語対応

# 4. VS Code編集
code paper.tex                     # Ctrl+Alt+B でビルド

# 5. または Neovim編集
nvim paper.tex                     # <leader>ll でコンパイル

# LaTeX utilities
latex-build      # latexmk -pdf -pvc (連続ビルド)
latex-clean      # latexmk -c (中間ファイル削除)
latex-cleanall   # latexmk -C (全削除)
```

### 開発ツール・AIプラットフォーム
- **Git** - バージョン管理
- **AI Platform** - Claude、GitHub Copilot統合開発支援
- **Docker** - コンテナ化
- **nix-direnv** - 10-100倍高速環境切り替え（Phase 6 完了）
- **crane** - Rust最適化ビルドシステム（Phase 6 完了）

## 📚 ドキュメント

- [CLAUDE.md](CLAUDE.md) - プロジェクト詳細情報
- [SECURITY.md](SECURITY.md) - セキュリティ設定
- [docs/](docs/) - 詳細ガイド
- [docs/todo/](docs/todo/) - 今後の実装予定タスク

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

## 📈 最新の成果

### 2025年7月15日 - Phase 6 実装完了 ✅

**Phase 6 完了項目 (100% 完了):**
- ✅ **nix-direnv統合**: 10-100倍高速開発環境切り替え
  - プロジェクト自動検出（Node.js, React, Vue, Rust, Go, Python）
  - パフォーマンス最適化とベンチマーク機能
  - テンプレート統合とヘルスチェック
- ✅ **crane Rust最適化**: 高速ビルドとクロスコンパイル
  - 依存関係分離キャッシュで大幅な高速化
  - x86_64, aarch64, WebAssembly対応
  - プロジェクト作成テンプレートとベンチマーク
- ✅ **統合開発環境**: Modern CLI + AI + 高速化の完全統合

**Phase 7 Advanced Features 計画中:**
- 🎯 **sops-nix**: 宣言的シークレット管理
- 🎯 **deploy-rs**: リモートマシン管理
- 🎯 **エンタープライズ機能**: チーム環境標準化

**利用可能なコマンド:**
```bash
# Phase 6 新機能体験
direnv-setup auto                 # プロジェクト自動環境設定
crane-create myapp binary         # 最適化Rustプロジェクト
crane-benchmark                   # ビルド性能測定
nix-direnv-health                # 環境統合診断

# Modern CLI体験
ll && bat README.md && rg "Phase" && h "build"

# AI開発支援  
ai-code-review && ai-deployment analyze && ai-docs generate

# 高度なヘルスチェック
modern-cli-health && ai-platform-health && dev-health
```

---

*最終更新: 2025年7月12日*