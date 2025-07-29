# 📁 プロジェクト構造

**最終更新**: 2025年7月15日  
**Phase**: 6完了後の最適化構造

## 🏗️ ディレクトリ構成

```
dotfiles/
├── 📄 Configuration Files
│   ├── .gitignore              # Git除外設定
│   ├── .gitleaks.toml         # シークレット検出設定
│   ├── .sops.yaml.example     # SOPS設定テンプレート
│   ├── justfile               # タスクランナー設定
│   ├── README.md              # メインドキュメント
│   ├── CLAUDE.md              # プロジェクト詳細情報
│   └── SECURITY.md            # セキュリティガイド
│
├── 📂 Core System (nix/)
│   ├── common/                # 共通設定モジュール
│   │   ├── development/       # 開発環境統合
│   │   │   ├── nix-direnv-integration.nix  # Phase 6: 高速環境切り替え
│   │   │   ├── crane-optimization.nix     # Phase 6: Rust最適化
│   │   │   ├── ai-platform/              # AI開発支援
│   │   │   ├── lsp/                      # Language Server
│   │   │   └── web/                      # Web開発環境
│   │   ├── themes/            # UI/カラーテーマ
│   │   └── overlays/          # Nixパッケージオーバーレイ
│   ├── darwin/                # macOS専用設定
│   ├── linux/                 # Linux専用設定
│   ├── wsl/                   # WSL専用設定
│   ├── android/               # Android専用設定
│   └── secrets/               # 暗号化シークレット管理
│
├── 📂 Application Configs (configs/)
│   ├── editors/               # エディター設定
│   │   └── nvim/             # Neovim設定
│   ├── terminals/             # ターミナル設定
│   │   ├── wezterm/          # WezTerm設定
│   │   └── zellij/           # Zellij設定
│   └── wm/                    # ウィンドウマネージャー設定
│
├── 📂 Development Templates (templates/)
│   ├── web/                   # Web開発テンプレート
│   │   ├── nextjs-fullstack/ # Next.js + TypeScript
│   │   ├── vue-typescript/   # Vue 3 + TypeScript
│   │   ├── node-api/         # Node.js REST API
│   │   └── docker-fullstack/ # マルチサービス Docker
│   ├── mobile/                # モバイル開発
│   │   ├── react-native/     # React Native + Expo
│   │   └── flutter/          # Flutter
│   ├── data/                  # データサイエンス
│   │   ├── python-ml/        # Python機械学習
│   │   └── r-analytics/      # R統計解析
│   ├── systems/               # システムプログラミング
│   │   ├── rust-cli/         # Rust CLI (crane最適化)
│   │   └── go-api/           # Go Web API
│   └── _shared/               # 共通ユーティリティ
│
├── 📂 Automation Scripts (scripts/)
│   ├── system-health-master.sh    # システムヘルスチェック
│   ├── system-auto-fix.sh         # 自動修復
│   ├── system-maintenance.sh      # メンテナンス
│   ├── performance-monitor.sh     # パフォーマンス監視
│   ├── template-manager.sh        # テンプレート管理
│   ├── project-create.sh          # プロジェクト作成
│   ├── web-create.sh             # Web開発支援
│   ├── session-migrate.sh        # tmux→Zellij移行
│   └── generate-health-dashboard.sh # ダッシュボード生成
│
├── 📂 Documentation (docs/)
│   ├── guides/                     # 詳細ガイド
│   │   ├── automation.md          # 自動化ガイド
│   │   ├── neovim.md              # Neovim設定ガイド
│   │   ├── web-development.md     # Web開発ガイド
│   │   └── wezterm.md             # WezTerm設定ガイド
│   ├── todo/                       # 今後の実装予定
│   │   ├── README.md              # タスク管理
│   │   ├── sops-nix-secret-management.md
│   │   ├── git-ssh-config-encryption.md
│   │   ├── dynamic-island-integration.md
│   │   ├── qmk-via-keyboard-integration.md
│   │   └── ollama-code-fix.md
│   ├── DEVELOPMENT_ENVIRONMENT_GUIDE.md  # 開発環境詳細
│   ├── PHASE6_COMPLETION_REPORT.md       # Phase 6完了レポート
│   ├── NIX_LIBRARY_IMPLEMENTATION_STATUS.md # 実装状況
│   └── README.md                         # ドキュメント索引
│
└── 📂 Build System
    ├── .github/                # GitHub Actions CI/CD
    ├── .devcontainer/          # Dev Container設定
    └── .config/                # ツール設定
```

## 🔧 主要機能別ファイルマップ

### Phase 6完了機能

#### nix-direnv統合 (10-100倍高速化)
- `nix/common/development/nix-direnv-integration.nix`
- コマンド: `direnv-setup`, `nix-direnv-health`, `direnv-benchmark`

#### crane Rust最適化
- `nix/common/development/crane-optimization.nix`
- `templates/systems/rust-cli/`
- コマンド: `crane-create`, `crane-build`, `crane-benchmark`

#### 統合開発環境
- `nix/common/development/` - 全モジュール統合
- `scripts/system-health-master.sh` - 統合ヘルスチェック

### Modern CLI Tools (Phase 5)
- `nix/common/development/cli-tools.nix`
- コマンド: `ll`, `cat`→`bat`, `find`→`fd`, `grep`→`rg`

### AI開発支援
- `nix/common/development/ai-platform/`
- `configs/editors/nvim/` - GitHub Copilot統合

### Web開発環境
- `templates/web/` - 全Webテンプレート
- `nix/common/development/web/` - Web開発環境

## 🧹 整理済み項目

### 削除されたディレクトリ/ファイル
- `backup-web-config/` - バックアップディレクトリ
- `home-manager/` - レガシー設定
- `test-*/` - テストディレクトリ
- `configs/python/`, `configs/ruby/` - 言語別設定（nix統合済み）
- `docs/reports/` - 古いレポート
- `docs/user/` - メインREADMEに統合

### 最適化された設定
- `.gitignore` - テストディレクトリとバックアップファイル除外強化
- ドキュメント構造簡素化
- Phase 6完了に合わせた構造最適化

---

**整理完了**: 2025年7月15日  
**次フェーズ**: Phase 7 - エンタープライズ機能・リモート管理統合