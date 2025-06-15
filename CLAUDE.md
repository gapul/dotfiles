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

## Claude Code 標準ワークフロー

Claude Codeがこのプロジェクトで作業する際の標準的なワークフローパターンです。

### 1️⃣ 事前準備フェーズ

**状況把握タスク:**
- `git status` で現在のブランチとgit状態確認
- `LS` や `Glob` でディレクトリ構造の理解  
- `Read` で既存の設定・ドキュメント確認
- `TodoRead` で既存タスク状況の把握

**重要ポイント:**
- 作業前に必ず現在の状態を把握する
- 変更が他の部分に与える影響を考慮する
- セキュリティファイル（.gitignore対象）に注意を払う

### 2️⃣ 作業計画フェーズ

**タスク管理:**
- `TodoWrite` でタスクリストを作成
- 優先度付け (high/medium/low)
- 複雑なタスクは段階的にブレークダウン
- 進捗状況を随時更新（pending → in_progress → completed）

**計画のコツ:**
- 大きなタスクは小さく分割する
- 依存関係を考慮した順序付け
- リスクの高い変更は慎重に計画

### 3️⃣ 実装フェーズ

**段階的実装:**
- 各タスクを開始時に `in_progress` に変更
- `Read` で既存ファイルの内容を確認してから `Edit` や `Write`
- 新機能実装・既存機能修正を段階的に実行
- 完了後は即座に `completed` に更新

**実装のベストプラクティス:**
- 既存ファイルの編集を新規作成より優先
- コメントは日本語で詳細に記載
- 2スペースインデント（YAML, JSON, Lua）を厳守
- `MultiEdit` で複数箇所の同時変更を効率化

### 4️⃣ 品質保証フェーズ

**ローカル検証手順:**
```bash
# 構文チェック
shellcheck scripts/*.sh
python3 .github/scripts/validate_toml.py

# 機能テスト
./install.sh --help
./setup.sh --help

# 依存関係チェック
scripts/check-dependencies.sh --verbose
```

**検証のポイント:**
- 新しいスクリプトは必ず実行可能権限を付与
- エラーが発生した場合は即座に修正
- 依存関係の問題を事前に検出

### 5️⃣ 統合フェーズ

**Git管理プロセス:**
1. `git status` で変更内容確認
2. `git diff` で変更詳細レビュー  
3. `git log` で最近のコミット履歴確認（コミットメッセージスタイル把握）
4. `git add .` でステージング
5. 詳細なコミットメッセージ作成
6. `git push origin main`

**コミットメッセージテンプレート:**
```
<変更内容の概要>

- <具体的な変更点1>
- <具体的な変更点2>
- <具体的な変更点3>

<技術的詳細や背景情報>

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

### 6️⃣ CI/CD確認フェーズ

**継続的統合確認:**
- `gh run list --limit 5` でGitHub Actions実行確認
- CI失敗時は `gh run view <run-id> --log-failed` で詳細確認
- エラーの即座修正とre-push
- 全てのテストが成功するまで対応継続

**CI失敗時の対応パターン:**
- Shellcheck警告: 除外設定や修正
- 依存関係エラー: パス修正や設定更新
- テスト失敗: ロジック修正や設定調整

### 7️⃣ ドキュメント保守フェーズ

**ドキュメント更新対象:**
- `README.md`: 機能追加時の使用方法更新
- `CLAUDE.md`: 新しいパターンや重要な学びの記録
- `docs/`: 詳細ガイドの追加・更新
- コード内コメント: 複雑なロジックの説明

**ドキュメント品質基準:**
- 具体的な例とコマンドを含む
- トラブルシューティング情報を提供
- セキュリティ考慮事項を明記

## 特徴的なパターン

### 並行処理最適化
- 複数のBashコマンドを1つのメッセージで同時実行
- 関連ファイルの並行読み取り
- 効率的な情報収集とバッチ処理

### エラー対応即応性  
- CI失敗の即座確認・修正
- Shellcheck警告の迅速対応
- 依存関係問題の自動検出と修正

### セキュリティ重視
- 個人情報ファイルの除外確認
- .gitignore の適切な管理
- セキュアな設定管理の維持

### 品質保証徹底
- 各段階での検証実施
- 自動テストとの連携
- 継続的改善の実践

## 📈 最新の成果と改善

### 2025年6月15日 - 大幅な機能拡張完了

#### 🌐 Browser MCP統合
- **Playwright MCP Server**: クロスブラウザ自動化
- **Puppeteer MCP Server**: Headless Chrome制御
- **Web情報収集**: 技術調査・設定例収集の自動化
- **フォーム操作**: 検索・入力・データ抽出

#### 📦 nix移行戦略の完成
- **包括的移行プラン**: 4段階・6週間の詳細計画
- **150+パッケージ分析**: Homebrew環境の完全調査
- **実用的設定**: nix-darwin + home-manager設定
- **ハイブリッド共存**: 安全な段階的移行戦略

#### 🖥️ ターミナルセッション永続化
- **tmux設定**: Yabai環境最適化
- **セッション管理**: プロジェクト別作業継続
- **macOS統合**: クリップボード連携・キーバインド

#### 🔗 依存関係管理システム
- **自動検証**: ファイル参照の整合性チェック
- **Pre-commit統合**: コミット前の品質保証
- **CI/CD統合**: GitHub Actionsでの自動検証

#### 📚 ドキュメント体系の充実
- **包括的ガイド**: 13種類の詳細ドキュメント
- **実用例**: 具体的なコマンドと使用例
- **トラブルシューティング**: よくある問題と解決方法

### 🎯 プロジェクトの成熟度

**システム管理:**
- ✅ 完全自動化されたdotfiles管理
- ✅ 依存関係の自動検証
- ✅ CI/CDによる品質保証
- ✅ セキュリティ重視の設計

**開発効率:**
- ✅ ターミナルセッション永続化
- ✅ ブラウザ自動化統合
- ✅ 段階的パッケージマネージャー移行
- ✅ プロジェクト別環境分離

**保守性:**
- ✅ モジュール化された設定
- ✅ 包括的なドキュメント
- ✅ 標準化されたワークフロー
- ✅ 継続的な品質管理

---

このワークフローと最新の機能により、効率的で品質の高い作業を継続的に実現し、プロジェクトの整合性と安全性を維持しています。