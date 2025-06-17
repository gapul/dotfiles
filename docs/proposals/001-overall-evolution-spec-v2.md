## `dotfiles` 総合進化プロジェクト：実装仕様書

* **ドキュメントバージョン**: 2.0
* **作成日**: 2025年6月17日
* **対象リポジトリ**: `yuki/dotfiles` (現在のコンテキスト)
* **目的**: 冗長性の排除、保守性の向上、宣言的管理の深化、そしてAIとの協調作業の最適化を通じて、`dotfiles`システムを再利用可能で堅牢な統合環境フレームワークへと進化させる。

### 1. プロジェクトの基本方針

以下の原則に基づき、本仕様書に記載されたリファクタリングと機能追加を遂行する。

* **単一責務・単一情報源の原則 (SRP & SSOT)**: 機能や設定の重複を排除し、すべての定義が唯一の信頼できる情報源から派生するように設計する。
* **宣言的管理の最大化 (Maximizing Declarative Management)**: `install.sh`のような命令的スクリプトへの依存を排除し、可能な限りNixによる宣言的な状態定義に置き換える。
* **AI協調のための明確化 (Clarity for AI Collaboration)**: AIが解釈・操作しやすいように、依存関係、設定スキーマ、操作インターフェースを明示的に定義する。

### 2. 実行フェーズと優先順位

本プロジェクトは以下の4フェーズに分けて実行する。前のフェーズが完了してから次のフェーズに進むこと。

* **Phase 1: 基盤安定化フェーズ (Priority: Critical)**
* **Phase 2: 構造的リファクタリングフェーズ (Priority: High)**
* **Phase 3: 機能拡張とプロセス改善フェーズ (Priority: Medium)**
* **Phase 4: 長期的な発展と高度化フェーズ (Priority: Low)**

---

### Phase 1: 基盤安定化フェーズ (Priority: Critical)

**目的**: 現在確認されている明らかな問題点を修正し、リファクタリングのための安定した基盤を構築する。

#### タスク 1.1: `starship.toml` の構文エラー修正
* **現状の問題**: `reports/config-dependencies-*.md`にて、`configs/terminal/starship.toml` の構文エラーが指摘されている。
* **実装仕様**:
    1.  対象ファイル `configs/terminal/starship.toml` を開く。
    2.  `starship config -` コマンドや公式ドキュメントのスキーマを参考に、無効なキーや値を修正する。
    3.  `.github/scripts/validate_toml.py` を実行し、検証が成功することを確認する。
* **対象ファイル**: `configs/terminal/starship.toml` (修正)

#### タスク 1.2: `.gitignore` のセキュリティパターン追加
* **現状の問題**: `reports/security-analysis-*.md`にて、一般的な機密情報ファイルのパターンが `.gitignore` に不足している。
* **実装仕様**:
    1.  ルートの `.gitignore` ファイルを開く。
    2.  ファイル末尾に以下のパターンを追記する。
        ```gitignore
        # Secret files & Environment variables
        *.key
        *.pem
        *.p12
        *.p8
        *.env
        secrets.*
        private.*
        ```
* **対象ファイル**: `.gitignore` (修正)

---

### Phase 2: 構造的リファクタリングフェーズ (Priority: High)

**目的**: システム全体の重複を排除し、保守性と一貫性を劇的に向上させる。

#### タスク 2.1: 設定デプロイメントの一元化
* **現状の問題**: `scripts/install.sh` と `home-manager` が、それぞれ設定ファイルのデプロイという同じ役割を担っている。
* **実装仕様**:
    1.  `scripts/install.sh` の `DOTFILES_LIST` で管理されている全ファイルを、`nix/home.nix` の `home.file` セクションに移行する。`home.file."<target-path>".source = ./path/to/source;` の形式で記述する。
    2.  `scripts/install.sh`, `scripts/backup.sh`, `scripts/restore.sh` のファイル操作ロジックを完全に削除し、これらのスクリプトを廃止するか、Nixの初回セットアップ用ラッパーとして役割を再定義する。
    3.  `README.md` のインストール手順を、`home-manager switch` を使う方法に更新する。
* **対象ファイル**: `nix/home.nix` (修正), `scripts/install.sh`, `scripts/backup.sh`, `scripts/restore.sh` (削除/修正), `README.md` (修正)

#### タスク 2.2: パッケージ分析スクリプトの統合
* **現状の問題**: `nix-package-optimizer.sh`, `analyze-homebrew-nix-migration.sh` など、類似機能を持つスクリプトが複数存在する。
* **実装仕様**:
    1.  `scripts/system-analyzer.sh` という名前で新しいスクリプトを作成する。
    2.  既存の分析スクリプト群の機能を、この新しいスクリプトにサブコマンドとして集約する（例: `package-optimize`, `discover-apps`）。
    3.  古いスクリプトファイルを削除し、関連ドキュメントの参照を更新する。
* **対象ファイル**: `scripts/system-analyzer.sh` (新規), 関連する古いスクリプト (削除)

#### タスク 2.3: UI設定の単一情報源 (SSOT) の確立
* **現状の問題**: フォントやカラーテーマが `wezterm.lua`, `sketchybar/colors.lua`, Neovim設定などに分散して定義されている。
* **実装仕様**:
    1.  `nix/common/theme.nix` を作成し、システムのベースとなるフォント名やカラーパレットを定義する。
    2.  `home.nix`で`theme.nix`をインポートし、`home.file`オプションと文字列展開を使い、WeztermやSketchybarのLua設定ファイルを動的に生成する。
* **対象ファイル**: `nix/common/theme.nix` (新規), `nix/home.nix` (修正), `configs/terminal/wezterm.lua` (削除/生成対象へ), `configs/wm/sketchybar/colors.lua` (削除/生成対象へ)

---

### Phase 3: 機能拡張とプロセス改善フェーズ (Priority: Medium)

**目的**: 宣言的管理の範囲を広げ、開発・メンテナンスのワークフローを効率化する。

#### タスク 3.1: 宣言的シークレット管理 (`sops-nix`) の導入
* **現状の問題**: 機密情報を手動で管理しているため、環境の完全な自動再現ができない。
* **実装仕様**:
    1.  `sops-nix` を `flake.nix` の `inputs` と `darwin.nix` の `modules` に追加する。
    2.  `secrets.yaml.example` を作成し、管理すべき機密情報の構造を定義する。
    3.  `darwin.nix` に `sops.secrets` を定義し、暗号化されたファイルがビルド時に復号・配置されるように設定する。
    4.  `SECURITY.md` を更新し、`sops-nix`のセットアップ方法と利用方法を記載する。
* **対象ファイル**: `flake.nix` (修正), `nix/darwin.nix` (修正), `secrets.yaml.example` (新規), `SECURITY.md` (修正)

#### タスク 3.2: Mac App Storeアプリの宣言的管理 (`mas-nix`) の導入
* **現状の問題**: `mas` で管理されるアプリが宣言的でない。
* **実装仕様**:
    1.  `flake.nix` に `mas-nix` をinputとして追加する。
    2.  `nix/darwin.nix` に `services.mas` モジュールを有効化し、`services.mas.packages` にApp StoreアプリのIDリストを定義する。
* **対象ファイル**: `flake.nix` (修正), `nix/darwin.nix` (修正)

#### タスク 3.3: タスクオーケストレーション層 (`justfile`) の導入
* **現状の問題**: よく使うコマンドやワークフローが、ドキュメントや個人の記憶に依存している。
* **実装仕様**:
    1.  プロジェクトルートに `justfile` を作成する。
    2.  `test`, `lint`, `docs`, `rebuild`, `update` などの共通タスクをレシピとして定義する。レシピは、本仕様書でリファクタリングされた後のスクリプトやコマンドを呼び出すようにする。
* **対象ファイル**: `justfile` (新規)

#### タスク 3.4: シェル履歴の高度化 (`atuin`)
* **現状の問題**: シェル履歴がマシンごとに分断され、検索性も低い。
* **実装仕様**:
    1.  `home.nix` に `programs.atuin.enable = true;` を追加する。
    2.  同期サーバの設定など、必要な初期設定を `programs.atuin.settings` に記述する。
* **対象ファイル**: `nix/home.nix` (修正)

---

### Phase 4: 長期的な発展と高度化フェーズ (Priority: Low)

**目的**: プロジェクトの適用範囲を広げ、将来的な発展のための基盤を整備する。

#### タスク 4.1: クロスプラットフォーム対応 (Linux)
* **現状の問題**: 設定がmacOS (`nix-darwin`) に特化している。
* **実装仕様**:
    1.  `nix/` ディレクトリを `common/` (OS共通) と `hosts/` (OS/ホスト固有) にリファクタリングする。
    2.  `flake.nix` を修正し、`darwinConfigurations` と `homeConfigurations` (for Linux) の両方を出力できるようにする。
    3.  Linux固有の設定（WM、パッケージ名など）を `hosts/linux-host/` ディレクトリに作成する。

#### タスク 4.2: CI/CDでのインテグレーションテスト導入
* **現状の問題**: CIは静的解析が中心で、ビルド後の動作確認は手動。
* **実装仕様**:
    1.  GitHub Actionsのワークフローに新しいジョブを追加する。
    2.  Nix Flakeを使い、テスト用のDockerコンテナをビルドする。
    3.  コンテナ内で「`zsh`がインストールされているか」「エイリアスが設定されているか」などの基本的な振る舞いを検証するテストを実行する。

---

### Claude Codeへの指示

上記の仕様書に基づき、Phase 1から順番にタスクを実行してください。各タスクの完了後には、指定された検証方法で変更が正しく適用されたことを確認し、その結果を報告してください。一つのタスクが完了・検証されてから、次のタスクに進んでください。各フェーズの完了ごとに、最終的なレビューを求めます。