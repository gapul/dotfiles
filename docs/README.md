# 📚 ドキュメント構造

dotfilesプロジェクトの包括的なドキュメントです。

## 📁 ディレクトリ構造

```
docs/
├── README.md                  # このファイル
├── guides/                    # セットアップ・設定ガイド
│   ├── setup.md              # 基本セットアップ
│   ├── development-environment.md  # 開発環境設定
│   └── automation.md         # 自動化設定
├── tutorials/                 # アプリケーション別チュートリアル
│   ├── neovim.md             # Neovim設定
│   └── wezterm.md            # WezTerm設定
├── reference/                 # リファレンス・API
│   ├── nix-configuration.md  # Nix設定詳細
│   ├── platform-support.md  # プラットフォーム対応
│   └── troubleshooting.md    # トラブルシューティング
└── Next_Step.md              # 次のステップ（アップグレードガイド）
```

## 🚀 はじめに

### 新規ユーザー向け
1. [セットアップガイド](guides/setup.md) - 基本的なインストールと設定
2. [開発環境ガイド](guides/development-environment.md) - 開発ツールの設定
3. [Neovimチュートリアル](tutorials/neovim.md) - エディター設定

### 既存ユーザー向け
- [自動化ガイド](guides/automation.md) - CI/CDとタスク自動化
- [プラットフォーム対応](reference/platform-support.md) - マルチプラットフォーム設定
- [次のステップ](Next_Step.md) - アップグレードと新機能

## 📖 ドキュメント分類

### ガイド (`guides/`)
実際の作業手順を説明する実用的なドキュメント：
- ステップバイステップの手順
- 設定例とベストプラクティス
- トラブルシューティング

### チュートリアル (`tutorials/`)
特定のツールやアプリケーションの使い方：
- アプリケーション固有の設定
- カスタマイズ方法
- 使用例

### リファレンス (`reference/`)
技術仕様とAPI情報：
- 設定オプション一覧
- プラットフォーム互換性
- エラー解決方法

## 🔧 ドキュメント管理

### 更新頻度
- **ガイド**: コア機能変更時
- **チュートリアル**: アプリケーション設定変更時
- **リファレンス**: 新機能追加時

### 貢献方法
1. ドキュメントの不備を発見した場合はIssueを作成
2. 改善提案はPull Requestで提出
3. 新しいチュートリアルの追加も歓迎

---

*最終更新: 2025年7月2日*