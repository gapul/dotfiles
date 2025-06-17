承知いたしました。これまでの議論の集大成として、今後の改善作業をClaude Codeが円滑に進めるための、新しい`CLAUDE.md`の内容を以下に提示します。

このドキュメントは、AIに対する明確な行動規範、利用可能なツール（API）、そして標準的な作業手順を定義することで、あなたとAIとの共同作業を新たなレベルへと引き上げます。

-----

# 🤖 Dotfiles Management System - Claude Code Operating Manual

このドキュメントは、Claude Codeがこのリポジトリで作業を行う際の、**唯一の信頼できる情報源 (Single Source of Truth)** です。全ての作業は、このマニュアルに記載された規範と手順に従って実行してください。

## 🎯 現在の最優先目標 (Current Top Priority Goal)

**[実装仕様書(docs/proposals/001-overall-evolution-spec-v2.md)](https://www.google.com/search?q=docs/proposals/001-overall-evolution-spec-v2.md)に基づき、Phase 1: 基盤安定化フェーズを完了させる。**

  * **タスク 1.1**: `starship.toml` の構文エラー修正
  * **タスク 1.2**: `.gitignore` のセキュリティパターン追加

完了後は、変更をコミットし、Phase 2の計画に移ります。

## ⚖️ Claude Code 行動規範 (Golden Rules)

以下のルールは、いかなる場合も**絶対に遵守**してください。

1.  **テスト駆動の徹底**:
      * **変更前**: 必ず `just test` を実行し、既存のテストが全て成功することを確認します。
      * **変更後**: コードを修正したら、再度 `just test` を実行し、自身の変更によってリグレッション（機能低下）が発生していないことを保証します。
2.  **機密情報の厳禁**:
      * いかなる機密情報（APIキー、パスワード等）もファイルに書き込みません。機密情報の管理は `sops-nix` を利用する計画があるため、それ以外の方法での扱いは禁止します。
3.  **ドキュメントの同期**:
      * スクリプトのインターフェースやコマンドの挙動を変更した場合、必ず `just docs` を実行して関連ドキュメントを自動更新します。
4.  **アトミックなコミット**:
      * 一つの関心事ごとにコミットを分割します。コミットメッセージは、本ドキュメントのテンプレートに従います。
5.  **APIの利用**:
      * 可能な限り、後述の `Repository API` で定義された高レベルなコマンド（`just`コマンド）を利用します。個別のスクリプトを直接実行するのは、APIが存在しない場合に限定します。

## 🛠️ Repository API (実行可能コマンド体系)

このリポジトリの操作は、以下の`justfile`で定義されたコマンドを通じて行うことを原則とします。この`justfile`は実装仕様書のタスクとして今後作成します。

```makefile
# Dotfiles Orchestration Layer (justfile)

# --- Quality Assurance ---
test: lint validate ## ✅ 全てのローカル検証を実行
lint: ## シェルスクリプトの静的解析
    shellcheck scripts/*.sh
validate: ## 設定ファイルの構文検証
    python3 .github/scripts/validate_toml.py

# --- Documentation ---
docs: ## 📖 ドキュメントを自動生成・更新
    ./scripts/generate-docs.sh # このスクリプトは今後作成

# --- Nix System Management ---
rebuild: ## 🚀 Nix-Darwinシステムを再構築
    cd nix && USER=yuki sudo darwin-rebuild switch --flake .
update: ## 🔄 Flakeを更新してシステムを再構築
    cd nix && nix flake update && just rebuild
check-nix: ## Nix設定の構文をチェック
    cd nix && nix flake check

# --- Maintenance ---
maintenance: ## ✨ 完全メンテナンスを実行
    ./scripts/nix-maintenance.sh maintenance
```

## ワークフロー：タスク実行の標準手順 (SOP)

全てのタスクは、以下の手順に従って実行してください。

1.  **[計画] Task Planning**:

      * `TodoRead`で現在のタスクリストを確認します。
      * 実行するタスクを`TodoWrite`で`in_progress`に更新します。

2.  **[分析] Context Analysis**:

      * `Read`で関連するファイル（実装仕様書、既存コード、関連ドキュメント）を読み込み、変更内容と影響範囲を完全に理解します。
      * スクリプトを修正する場合は、コード先頭の`@dependencies`ヘッダー（今後追加予定）を確認します。

3.  **[実装] Implementation**:

      * `Edit`や`Write`を使い、仕様書に基づいてコードの変更を正確に実行します。
      * 可能な限り、`Repository API`で定義されたコマンドを利用します。

4.  **[検証] Validation & Self-Correction**:

      * コードの変更後、**必ず`just test`を実行します**。
      * **テストが失敗した場合**: エラー出力を詳細に分析し、**自ら問題を特定してコードを修正**します。修正後、再度`just test`を実行し、成功するまでこのループを繰り返します。
      * **テストが成功した場合**: 次のステップへ進みます。

5.  **[文書化] Documentation**:

      * スクリプトの挙動やインターフェースに変更があった場合は、**必ず`just docs`を実行**し、ドキュメントとの同期を取ります。

6.  **[提出] Commit & Propose**:

      * `git status`, `git diff`で最終的な変更内容を確認します。
      * 以下のテンプレートに従い、詳細なコミットメッセージを作成し、変更を提案します。

    **コミットメッセージテンプレート**:

    ```
    feat(scope): 変更内容の簡潔な説明

    実装仕様書「(タスク番号): (タスク名)」に基づき、以下の変更を実施。

    - 変更点1の詳細な説明。
    - 変更点2の詳細な説明。

    これにより、(達成される価値や解決される問題)が実現される。
    全てのローカルテスト(`just test`)は成功済み。

    Co-Authored-By: Claude <noreply@anthropic.com>
    ```

## プロジェクトアーキテクチャ概要

  * **宣言的管理**: Nix (`nix-darwin`, `home-manager`) がシステムの核。
  * **設定の単一情報源 (SSOT)**:
      * **UIテーマ**: `nix/common/theme.nix`（今後作成）が全てのUIのカラースキームとフォントを定義する。
      * **デプロイ**: `home.nix`が全てのドットファイルの配置を管理する。
  * **命令的処理**:
      * `scripts/`内のシェルスクリプトは、`justfile`を通じて抽象化されたタスクとして実行される。
  * **AIとの連携**:
      * この`CLAUDE.md`が、AIの振る舞いを定義する最上位のドキュメントとなる。

## 📚 主要ドキュメントと情報源 (Key Documents)

作業の際は、以下のドキュメントを主要な情報源として常に参照してください。

  * **本ファイル (`CLAUDE.md`)**: あなた自身の行動規範とワークフロー。
  * **実装仕様書**: `docs/proposals/001-overall-evolution-spec-v2.md` - 現在進行中のプロジェクトの具体的な指示書。
  * `docs/nix/HOMEBREW_STRATEGY.md` : Homebrewで管理するパッケージとその理由を記載したリスト。
  * `nix/common/theme.nix` : UI設定の唯一のマスターファイル。

## ⚙️ プロジェクトの成果と履歴

(このセクションは、完了したフェーズの成果を記録するために継続して使用します)

  * **2025-06-17**: `dotfiles`総合進化プロジェクト開始。実装仕様書v2.0が承認される。
  * **2025-06-16**: Nix移行プロジェクト完了。宣言的環境管理の基盤を確立。
  * **2025-06-15**: MCP（Model Context Protocol）の接続問題を完全解決。