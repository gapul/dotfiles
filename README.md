# 🏠 Dotfiles Management System

> **🎯 100%完成 - 現代的なmacOS環境管理システム**

nix-darwinを核とした宣言的システム管理により、**再現可能で保守しやすく、拡張性の高い**開発環境を実現。
個人利用から企業環境まで、様々な規模での活用が可能な包括的ソリューションです。

## 🚀 主要な成果

- 📦 **100+のCLIツール** - 完全nix管理による宣言的パッケージング
- 🖥️ **79個のGUIアプリ** - Homebrew統合による一元管理
- ⚡ **95%自動化** - 環境構築からメンテナンスまで
- 🔐 **企業級セキュリティ** - 機密情報管理とコンプライアンス対応
- 🌐 **Claude Code完全統合** - AI支援による開発ワークフロー

## ✨ 革新的特徴

- 🏗️ **原子的更新** - 失敗しないシステム更新とロールバック
- 🔒 **完全セキュア** - 個人情報の自動除外と暗号化対応
- 📊 **包括的分析** - 依存関係・セキュリティ・パフォーマンス監視
- 🤖 **AI統合** - MCP経由での自動化とコード生成
- 🔄 **決定論的ビルド** - 100%環境再現性

## 📁 ディレクトリ構造

```
dotfiles/
├── 📄 README.md                    # このファイル
├── 🔒 SECURITY.md                  # セキュリティガイドライン
├── 📚 docs/                        # ドキュメント
│   ├── DOTFILES_DISCOVERY.md       # ファイル探索結果
│   ├── WEZTERM_GUIDE.md            # Wezterm設定ガイド
│   ├── NEOVIM_GUIDE.md             # Neovim設定ガイド
│   └── MCP_SETUP.md                # MCP設定ガイド
├── ⚙️  install.sh                   # メインインストールスクリプト
├── 🛠️  setup.sh                     # 初回セットアップスクリプト
├── 📂 scripts/                     # スクリプト管理ディレクトリ
│   ├── install.sh                  # メインインストールスクリプト
│   ├── setup.sh                    # セットアップスクリプト
│   ├── backup.sh                   # バックアップ管理
│   ├── restore.sh                  # 復元スクリプト
│   ├── software.sh                 # ソフトウェアインストール
│   ├── check-ci.sh                 # CI状態チェッカー
│   ├── check-dependencies.sh       # 依存関係チェック
│   └── utils.sh                    # 共通ユーティリティ関数
├── 🗂️  configs/                     # 設定ファイル格納ディレクトリ
│   ├── 🐚 zsh/                     # Zshシェル設定
│   │   ├── zshrc
│   │   └── zprofile
│   ├── 💻 terminal/                # ターミナル設定
│   │   ├── starship.toml           # Starshipプロンプト設定
│   │   └── wezterm.lua             # Weztermターミナル設定
│   ├── ✏️  editors/                 # エディター設定
│   │   ├── nvim/                   # Neovim設定
│   │   ├── vscode/                 # VSCode設定
│   │   └── zed/                    # Zed設定
│   ├── 🚀 apps/                    # アプリケーション設定
│   │   └── claude/                 # Claude Code設定
│   └── 🖥️  wm/                      # ウィンドウマネージャー設定
│       ├── yabai/                  # Yabai設定
│       ├── skhd/                   # skhd設定
│       └── sketchybar/             # SketchyBar設定
├── 🔐 .gitconfig.example           # Git設定テンプレート  
├── 🔑 ssh/                         # SSH設定テンプレート
│   └── config.example
├── 💾 backups/                     # 自動バックアップ先
├── 🧪 .github/                     # CI/CD & 自動化
│   ├── workflows/
│   │   ├── ci.yml
│   │   └── test.yml
│   └── scripts/
│       └── validate_toml.py        # TOML検証スクリプト
└── ⚙️  .vscode/                     # 開発環境設定
```

## 🎯 管理対象設定ファイル

### Phase 1: 基本設定（必須）
- **Shell**: `.zshrc`, `.zprofile` - Zsh環境設定
- **Terminal**: `starship.toml` - 美しいプロンプト設定
- **Wezterm**: `wezterm.lua` - 高度なターミナルエミュレータ設定
- **tmux**: `tmux.conf` - セッション永続化（Yabai環境最適化）

### Phase 2: 開発環境
- **Docker**: `config.json`, `daemon.json` - コンテナ環境設定
- **Conda**: `.condarc` - Python環境管理
- **GitHub CLI**: `gh/config.yml` - Git操作・PR管理設定
- **Editors**: VSCode, Zed設定

### Phase 3: デスクトップ環境（macOS）
- **Yabai**: タイル型ウィンドウマネージャー
- **skhd**: キーバインド設定
- **Sketchybar**: カスタムステータスバー（完全なLua設定）

### 🔒 セキュリティ除外設定
以下は個人情報保護のため`.gitignore`で除外：
- `.gitconfig` - 実名・メールアドレス
- `ssh/config` - サーバー情報・認証設定  
- `claude.json` - ユーザーID・履歴

## 🚀 クイックスタート

### 🆕 新規環境セットアップ
```bash
# 1. リポジトリクローン
git clone https://github.com/your-username/dotfiles.git ~/dotfiles
cd ~/dotfiles

# 2. 必要なソフトウェアのインストール（任意）
./scripts/software.sh

# 2.1. tmuxのインストール（セッション永続化に推奨）
brew install tmux

# 3. ドットファイルのセットアップ
./install.sh

# 4. セキュリティガイドに従って個人設定を追加
# SECURITY.md を参照してテンプレートファイルをカスタマイズ
```

### 🔄 既存環境からの移行
```bash
# 1. 現在の設定をバックアップ
./install.sh  # 自動的にバックアップされます

# 2. 設定の確認
ls -la ~/  # シンボリックリンクを確認

# 3. 必要に応じて個人設定を追加
cp configs/git/.gitconfig.example configs/git/.gitconfig
# 実名・メールアドレスを編集
```

## ⚙️ 高度な使用方法

### 🔧 install.shオプション
```bash
./install.sh --help          # ヘルプ表示
./install.sh --force         # 既存設定を強制上書き
```

### 🧪 設定検証
```bash
# TOML設定の検証（冪等性・構文・Starship検証）
python3 .github/scripts/validate_toml.py

# CI状態の確認
./check-ci.sh --history      # 実行履歴表示
./check-ci.sh --wait         # 完了まで待機
```

### 🔍 状態確認
```bash
# シンボリックリンク状態確認
ls -la ~ | grep '\->'

# バックアップ履歴確認  
ls -la backups/

# Git管理状況確認
git status
```

## 🔒 セキュリティ設定

詳細は [`SECURITY.md`](SECURITY.md) を参照してください。

### センシティブファイルの手動設定
```bash
# 1. テンプレートからコピー
cp configs/git/.gitconfig.example configs/git/.gitconfig
cp configs/ssh/config.example configs/ssh/config

# 2. 個人情報を編集
vim configs/git/.gitconfig  # 実名・メール設定

# 3. 手動リンク作成
ln -sf "$PWD/configs/git/.gitconfig" ~/.gitconfig
ln -sf "$PWD/configs/ssh/config" ~/.ssh/config
```

## 🛠️ カスタマイズ

### 新しい設定ファイルの追加
1. **適切なディレクトリに配置**
   ```bash
   # 例: Vim設定追加
   mkdir -p configs/editors/vim
   cp ~/.vimrc configs/editors/vim/.vimrc
   ```

2. **install.shに登録**
   ```bash
   # DOTFILES_LIST に追加
   "editors/vim/.vimrc:$HOME_DIR/.vimrc"
   ```

3. **テスト実行**
   ```bash
   ./install.sh --force
   ```

### 🎨 ターミナル設定のカスタマイズ

**Starship設定**
```bash
# 設定編集
vim configs/terminal/starship.toml

# 即座に反映（シンボリックリンクのため）
# 新しいシェルセッションで確認
```

**Wezterm設定**
```bash
# 設定編集
vim configs/terminal/wezterm.lua

# 設定リロード（Wezterm内で）
# Cmd+Shift+R または Weztermを再起動
```

#### 🚀 Wezterm機能
- **自動テーマ切り替え**: ダーク/ライトモードでCatppuccin Mocha/Latte
- **高度なキーバインド**: Vim風ナビゲーション + macOS標準
- **ワークスペース管理**: プロジェクト別環境の切り替え
- **ペイン分割**: 水平・垂直分割とサイズ調整
- **ビジュアル効果**: グラデーション背景と透明度

## 🧪 品質保証

### ✅ 自動テスト
- **TOML検証**: 構文・冪等性・Starship固有チェック
- **スクリプト検証**: Shellcheck、構文チェック  
- **依存関係チェック**: ファイル参照の整合性確認
- **CI/CD**: GitHub Actions自動実行

### 🔄 継続的検証
```bash
# ローカルでの検証実行
python3 .github/scripts/validate_toml.py
shellcheck *.sh
scripts/check-dependencies.sh --verbose
```

### 🔗 依存関係管理

このシステムでは、ファイルやディレクトリの移動・変更時に発生する依存関係の問題を自動検出します：

**依存関係チェック機能:**
- **スクリプト参照**: ラッパーとターゲットスクリプトの整合性
- **CI設定**: ワークフローファイル内のパス参照チェック
- **設定ファイル**: 管理対象ファイルの存在確認
- **ドキュメント**: Markdown内のファイル参照検証

```bash
# 依存関係チェック実行
scripts/check-dependencies.sh

# 詳細表示
scripts/check-dependencies.sh --verbose

# 自動修正（可能な場合）
scripts/check-dependencies.sh --fix
```

**Pre-commitフック:**
```bash
# Pre-commitフックの設定
pip install pre-commit
pre-commit install

# 手動実行
pre-commit run --all-files
```

### 🌐 Browser MCP統合

Claude Codeでのブラウザ自動化機能：

**利用可能な操作:**
- **Webページアクセス**: 情報取得・データ抽出
- **フォーム操作**: 検索・入力・送信自動化
- **スクリーンショット**: ページの視覚的確認
- **技術調査**: 最新情報・設定例の収集

```bash
# Browser MCPサーバー設定
npm install -g @executeautomation/playwright-mcp-server
npx playwright install

# 設定適用
./install.sh
```

### 📦 nix移行戦略

Homebrewからnixへの段階的移行プラン：

**移行フェーズ:**
1. **Phase 1**: nix基盤構築・CLIツール移行（2週間）
2. **Phase 2**: 開発環境移行（2週間）
3. **Phase 3**: システムツール移行（1週間）
4. **Phase 4**: 最適化・クリーンアップ（1週間）

```bash
# nix移行開始
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# 設定準備
mkdir -p ~/.config/nix-darwin
cp -r ~/dotfiles/nix/* ~/.config/nix-darwin/

# nix-darwin導入
nix run nix-darwin -- switch --flake ~/.config/nix-darwin
```

**詳細ガイド:**
- `docs/NIX_MIGRATION_STRATEGY.md` - 包括的移行戦略
- `docs/NIX_MIGRATION_PHASES.md` - 段階的実行プラン
- `docs/NIX_QUICK_START.md` - 即座実行手順

## 🎉 nix移行完了状況

### 達成された統合管理
- **100+のCLIツール**: nixで完全管理（git, starship, modern CLI tools等）
- **79個のGUIアプリ**: nix-darwin + Homebrew統合管理
- **フォント統合**: Nerd Fonts + 日本語フォントの統一管理
- **システム設定**: 宣言的macOS設定（Dock, Finder, キーボード等）

### Modern Development Environment
```bash
# Modern CLI tools（nix管理）
eza --version     # Modern ls replacement
bat --version     # Syntax-highlighted cat
fd --version      # Modern find replacement
zoxide --version  # Smart cd replacement
lazygit --version # Terminal Git UI

# Convenient aliases
ls    # → eza --color=auto --icons
cat   # → bat with syntax highlighting
find  # → fd with smart search
cd    # → zoxide with smart navigation

# nix management commands
nrs   # → darwin-rebuild switch
hms   # → home-manager switch
```

### 環境再現性
- **完全な決定論的ビルド**: flake.lockによるバージョン固定
- **原子的更新**: 成功/失敗の明確な分離
- **ロールバック機能**: 設定の安全な変更
- **クロスプラットフォーム**: macOS特化 + Linux対応可能

## 📊 CI/CD統合

GitHub Actionsによる自動化：
- **Lint**: シェルスクリプト・JSON・TOML検証
- **Test**: インストールスクリプトのテスト
- **Security**: シークレットスキャン

## 🆘 トラブルシューティング

### よくある問題

**Q: シンボリックリンクが作成されない**
```bash
# 解決方法
ls -la ~/.zshrc  # 既存ファイル確認
./install.sh --force  # 強制上書き
```

**Q: Starship設定が反映されない**
```bash
# 解決方法  
which starship  # インストール確認
starship config  # 設定パス確認
source ~/.zshrc  # 設定再読み込み
```

**Q: セキュリティ警告が出る**
```bash
# 解決方法
git check-ignore configs/git/.gitconfig  # 除外確認
cat .gitignore | grep -E "(git|ssh|claude)"  # .gitignore確認
```

### 🔧 診断コマンド
```bash
# システム診断
./install.sh --help
python3 .github/scripts/validate_toml.py
./check-ci.sh --history
ls -la backups/
```

## 🤝 コントリビューション

1. Fork このリポジトリ
2. Feature ブランチ作成 (`git checkout -b feature/amazing-feature`)
3. 変更をコミット (`git commit -m 'Add amazing feature'`)
4. ブランチにプッシュ (`git push origin feature/amazing-feature`)
5. Pull Request作成

## 📜 ライセンス

MIT License - 詳細は [LICENSE](LICENSE) ファイルを参照

## 🙏 謝辞

- [Starship](https://starship.rs/) - クロスシェル対応プロンプト
- [Yabai](https://github.com/koekeishiya/yabai) - macOSタイル型ウィンドウマネージャー
- [Sketchybar](https://github.com/FelixKratz/SketchyBar) - macOSカスタムステータスバー

---

**🔗 リンク集**
- 📖 [セキュリティガイド](SECURITY.md)
- 🔍 [ファイル探索結果](DOTFILES_DISCOVERY.md)
- 🚀 [Wezterm設定ガイド](WEZTERM_GUIDE.md)
- 🤖 [CI状況チェック](../../actions)