# Slidev Presentations

このリポジトリは[Slidev](https://sli.dev)を使用したプレゼンテーション管理用です。

## 🚀 クイックスタート

### 環境準備

```bash
# direnvを有効化（自動環境構築）
direnv allow

# または手動でNix環境に入る
nix develop
```

### 新しいプレゼンテーション作成

```bash
# 新しいプレゼンテーションを作成
nix run .#new -- my-presentation

# プレゼンテーションディレクトリに移動
cd my-presentation

# 開発サーバー起動
npm run dev
```

### 既存のプレゼンテーション

```bash
# プレゼンテーションディレクトリで
npm run dev      # 開発サーバー起動
npm run build    # 本番ビルド
npm run export   # PDF/PNG エクスポート
```

## 📁 構造

```
slides/
├── flake.nix              # Nix開発環境定義
├── .envrc                 # direnv設定
├── presentation-1/        # プレゼンテーション1
│   ├── slides.md         # スライド内容
│   ├── package.json      # 依存関係
│   └── .envrc            # 環境設定
├── presentation-2/        # プレゼンテーション2
└── ...
```

## 🛠 利用可能なツール

Nix環境には以下が含まれています:

- **Node.js 22** - JavaScript実行環境
- **npm/pnpm/yarn** - パッケージマネージャー
- **Slidev CLI** - プレゼンテーション作成ツール
- **Git/GitHub CLI** - バージョン管理
- **ImageMagick/FFmpeg** - 画像・動画処理
- **Chromium** - ブラウザ（エクスポート用）
- **Neovim/VSCode** - エディタ

## 📝 Slidev機能

- **Markdown**ベースのスライド作成
- **テーマ**システム（npmで共有可能）
- **コードハイライト**とライブコーディング
- **Vueコンポーネント**の埋め込み
- **録画機能**とカメラビュー
- **PDF/PNG/SPA**へのエクスポート
- **ライブリロード**開発サーバー

## 🎨 テーマとカスタマイズ

利用可能なテーマ:
- `default` - デフォルトテーマ
- `seriph` - よりモダンなテーマ
- `apple-basic` - Apple風シンプルテーマ
- `bricks` - ブロック調デザイン
- その他多数...

詳細は[Slidev テーマ](https://sli.dev/themes/gallery.html)を参照

## 🔗 参考リンク

- [Slidev公式サイト](https://sli.dev)
- [Slidevドキュメント](https://sli.dev/guide/)
- [テーマギャラリー](https://sli.dev/themes/gallery.html)
- [Nix Flakes](https://nixos.wiki/wiki/Flakes)