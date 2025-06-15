# Homebrew → nix 移行戦略

> **安全で効率的なパッケージ管理移行計画**

## 🎯 移行目標

### なぜnixに移行するのか
- **再現性**: 完全な環境再現とバージョン固定
- **宣言的管理**: 設定ファイルでのパッケージ状態管理
- **ロールバック**: 確実な環境復元機能
- **分離**: プロジェクト別環境の完全分離
- **一貫性**: Linux/macOS間での統一管理

### 移行後の理想状態
- **nix-darwin**: macOS環境の宣言的管理
- **home-manager**: ユーザー環境の詳細制御
- **flakes**: 再現可能な環境定義
- **dotfiles統合**: 既存dotfiles管理との融合

## 📊 移行アプローチ戦略

### 🔄 ハイブリッド共存期間（推奨）

完全移行前に安全な共存期間を設ける：

```
Phase 1: nix導入・基本ツール移行（2-4週間）
Phase 2: 開発環境移行・検証（2-3週間）  
Phase 3: システムツール移行（1-2週間）
Phase 4: Homebrew段階的削除（1週間）
```

### 🎨 管理方針の選択

#### A) **nix-darwin + home-manager**（推奨）
```
システム全体をnixで宣言的管理
├── システムパッケージ（nix-darwin）
├── ユーザー環境（home-manager）  
└── 開発環境（direnv + flakes）
```

**メリット:**
- 完全な再現性と宣言的管理
- ロールバック・世代管理
- プロジェクト別環境分離

**デメリット:**
- 学習コストが高い
- デバッグが複雑

#### B) **nix + brew併用**（段階的）
```
用途別パッケージマネージャー分離
├── 開発ツール → nix
├── システムツール → nix-darwin
└── GUIアプリ → Homebrew
```

## 🗺️ 段階的移行ロードマップ

### Phase 1: 基盤構築（Week 1-2）

**目標**: nixインフラ構築とCLIツール移行

```bash
# 1. nixインストール
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# 2. nix-darwin セットアップ
nix run nix-darwin -- switch --flake ~/.config/nix-darwin

# 3. home-manager 統合
nix run home-manager/master -- init --switch
```

**移行対象パッケージ:**
- `git`, `gh`, `jq`, `ripgrep`, `tree`
- `neovim`, `starship`, `tmux`
- `shellcheck`, `python`, `node`

### Phase 2: 開発環境移行（Week 3-4）

**目標**: 開発ツールチェーン完全移行

**移行対象:**
- エディター: `neovim`, `vscode`, `zed`
- 言語環境: `python`, `node`, `go`, `rust`
- ビルドツール: `make`, `cmake`
- コンテナ: `docker`（要検証）

**検証項目:**
- 既存プロジェクトでの動作確認
- IDE統合の正常性
- パフォーマンス比較

### Phase 3: システムツール移行（Week 5-6）

**目標**: Yabai環境ツール移行

**重要な検証対象:**
- `yabai`, `skhd`, `sketchybar`（カスタムTaps）
- `wezterm`
- システム統合の確認

**リスク対策:**
- Homebrew環境をバックアップ保持
- 段階的テストと即座復旧体制

### Phase 4: クリーンアップ（Week 7）

**目標**: Homebrew依存の段階的削除

```bash
# 不要パッケージの特定
brew deps --tree --installed > brew_deps_backup.txt

# 段階的削除
brew uninstall --ignore-dependencies <package>
```

## 🏗️ nix設定アーキテクチャ

### ディレクトリ構造
```
dotfiles/
├── nix/
│   ├── flake.nix              # メインエントリポイント
│   ├── flake.lock             # バージョン固定
│   ├── darwin.nix             # macOS システム設定
│   ├── home.nix               # ユーザー環境設定
│   ├── packages/              # パッケージ定義
│   │   ├── development.nix    # 開発ツール
│   │   ├── system.nix         # システムツール
│   │   └── media.nix          # メディアツール
│   └── overlays/              # カスタムパッケージ
└── configs/                   # 既存dotfiles（継続使用）
```

### 設定管理統合
```nix
# home.nix での dotfiles 統合例
home.file.".zshrc".source = ../configs/zsh/zshrc;
home.file.".config/starship.toml".source = ../configs/terminal/starship.toml;
```

## ⚠️ リスクと対策

### 高リスク項目

1. **カスタムTaps (yabai, skhd, sketchybar)**
   - **対策**: nixpkgs-unstableでの対応確認
   - **代替**: 必要時のみHomebrew併用

2. **日本語環境・フォント**
   - **対策**: fonts.nix での明示的管理
   - **検証**: 日本語入力・表示の確認

3. **システムサービス (sketchybar)**
   - **対策**: LaunchAgent設定の移行
   - **テスト**: サービス起動の確認

### 中リスク項目

1. **GUIアプリケーション**
   - **戦略**: nix-darwin casks vs Homebrew併用
   - **判断**: アプリごとの対応状況確認

2. **Python/Node環境**
   - **対策**: direnv + flakes でプロジェクト分離
   - **移行**: 段階的な環境移行

## 🔧 運用戦略

### 日常運用

```bash
# システム更新
darwin-rebuild switch --flake ~/.config/nix-darwin

# ユーザー環境更新  
home-manager switch --flake ~/.config/nix-darwin

# プロジェクト環境
cd project && direnv allow
```

### バックアップ・復旧

```bash
# 設定世代管理
nix-env --list-generations
darwin-rebuild --rollback

# 完全バックアップ
nixos-rebuild build --flake .#backup
```

### 継続的メンテナンス

1. **月次**: flake inputs 更新
2. **週次**: garbage collection
3. **日次**: 設定変更の動作確認

## 📈 成功指標

### 移行完了の判定基準

1. **機能性**: 全開発タスクがnix環境で実行可能
2. **パフォーマンス**: Homebrew環境と同等以上の性能
3. **安定性**: 7日間の継続使用でクラッシュなし
4. **再現性**: 新環境での完全復元成功

### 緊急時復旧計画

```bash
# Homebrew環境即座復旧
brew bundle install --file=Brewfile.backup

# nix無効化
sudo launchctl unload /Library/LaunchDaemons/org.nixos.nix-daemon.plist
```

この戦略により、リスクを最小化しながら確実にnix環境への移行を実現します。