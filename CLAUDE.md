# Dotfiles Management System - Claude Code Memory

## プロジェクト概要

このプロジェクトは、macOS環境でのドットファイルを安全かつ効率的に管理するための完全なシステムです。

### 主要特徴
- シンボリックリンクベースの設定管理
- 自動バックアップ機能
- Phase別の段階的設定導入
- セキュリティを重視した個人情報除外
- CI/CD統合による品質保証

## アーキテクチャ

### ディレクトリ構造
```
dotfiles/
├── configs/           # 設定ファイル格納
│   ├── shell/         # Zsh設定
│   ├── terminal/      # Starship + Wezterm設定
│   ├── editors/       # エディター設定（VSCode, Zed, Neovim）
│   ├── development/   # 開発ツール設定
│   ├── cli/           # CLIツール設定
│   ├── wm/            # ウィンドウマネージャー設定
│   └── apps/          # アプリケーション設定
├── backups/           # 自動バックアップ
└── .github/           # CI/CD設定
```

### 管理対象設定
1. **Phase 1 (必須)**: Shell、Terminal、プロンプト設定
2. **Phase 2 (開発)**: Docker、Conda、GitHub CLI、エディター
3. **Phase 3 (UI)**: Yabai、skhd、Sketchybar（macOS）

## コーディング規約

### シェルスクリプト
- Bashでの実装、`set -euo pipefail`を使用
- エラーハンドリングを徹底
- ログ関数（log_info, log_success, log_warning, log_error）を使用
- 2スペースインデント

### 設定ファイル
- 2スペースインデント（YAML, JSON, Lua）
- コメントは日本語で詳細に記載
- セキュリティ重視（個人情報を含むファイルは.gitignore）

### Neovim設定
- Lua設定、LazyNvimプラグインマネージャー使用
- Catppuccinテーマでターミナルと統一
- モジュール化された設定構造

## 開発フロー

### 新機能追加手順
1. `configs/`下に設定ファイル配置
2. `install.sh`のDOTFILES_LISTに追加
3. テスト実行（`./install.sh --force`）
4. CI検証（TOML、シェルスクリプト検証）

### ファイル管理
- セキュリティファイル（.gitconfig, ssh/config, claude.json）は除外
- .exampleファイルでテンプレート提供
- バックアップは自動的にタイムスタンプ付きで作成

## 重要なコマンド

### インストール・管理
```bash
./install.sh              # 標準インストール
./install.sh --force      # 強制上書き
./install.sh --list-backups  # バックアップ一覧
./setup.sh                # 初回セットアップ
```

### Claude Codeクイックコマンド
プロジェクト内で以下のコマンドが利用可能：
- `install` - 標準インストール実行
- `install-force` - 強制上書きインストール
- `setup` - 初回セットアップ実行
- `backup-list` - バックアップ一覧表示
- `validate` - 設定ファイル検証
- `test` - 全体テスト実行

### 検証・メンテナンス
```bash
python3 .github/scripts/validate_toml.py  # TOML検証
./check-ci.sh             # CI状態確認
shellcheck *.sh           # シェルスクリプト検証
```

### Neovim関連
```bash
nvim                      # 起動（初回はプラグイン自動インストール）
:checkhealth              # 設定状態確認
:Lazy                     # プラグイン管理
:Mason                    # LSP管理
```

### Claude Code統合（Neovim内）
```vim
<leader>cc                # Claude Code起動
<leader>cf                # 現在のファイルレビュー
<leader>cq                # クイッククエリ
<leader>cs                # 選択範囲説明（Visual mode）
<leader>cg                # テスト生成
<leader>cd                # ドキュメント生成
<leader>co                # コード最適化
```

### MCP（Model Context Protocol）サーバー
設定済みのMCPサーバー：
- **filesystem**: `/Users/yuki/dotfiles`の安全なファイル操作
- **git**: Gitリポジトリの読み取り・検索・操作
- **github**: GitHub統合（Issue/PR管理）
- **brave-search**: Web検索とドキュメント検索
- **figma-dev-mode**: Figmaデザインからコード生成（SSE接続）

MCPサーバー管理：
```bash
claude mcp list           # 設定済みサーバー一覧
claude mcp add <name> <command> [args]  # サーバー追加
claude mcp remove <name>  # サーバー削除
```

## セキュリティ方針

### 除外ファイル
- `.gitconfig` - 実名・メールアドレス
- `ssh/config` - サーバー情報・認証設定
- `claude.json` - ユーザーID・履歴

### テンプレート提供
- 各除外ファイルに対応する.exampleファイルを提供
- セットアップ手順をSECURITY.mdに記載

## トラブルシューティング

### よくある問題
1. **シンボリックリンク作成失敗**: `--force`オプション使用
2. **Starship設定反映されない**: `source ~/.zshrc`実行
3. **Neovim起動エラー**: `:checkhealth`で診断

### デバッグ方法
```bash
DEBUG=true ./install.sh   # デバッグモード
ls -la ~ | grep '\->'     # シンボリックリンク確認
```

## メンテナンス

### 定期作業
- バックアップ整理（7日以上前は自動削除可能）
- CI状態確認
- 設定ファイルの更新確認

### アップデート方針
- 破壊的変更は避ける
- 既存設定の互換性維持
- 段階的導入（Phase別）

---

このメモリファイルにより、Claude Codeは本プロジェクトの構造、規約、運用方法を理解し、一貫性のある支援を提供できます。