# nix移行 段階的実行プラン

> **安全で確実な4段階移行手順**

## 🎯 移行フェーズ概要

| Phase | 期間 | 目標 | リスク |
|-------|------|------|--------|
| **Phase 1** | 2週間 | nix基盤構築・CLIツール | 低 |
| **Phase 2** | 2週間 | 開発環境移行 | 中 |  
| **Phase 3** | 1週間 | システムツール移行 | 高 |
| **Phase 4** | 1週間 | Homebrew削除・最適化 | 低 |

---

## 🔧 Phase 1: nix基盤構築（Week 1-2）

### 📋 実行チェックリスト

#### Day 1-2: nix基本インストール

```bash
# ✅ 1. Determinateシステム版nixインストール
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# ✅ 2. nix設定確認
nix --version
which nix

# ✅ 3. flakes有効化確認
nix-env --version
```

#### Day 3-4: nix-darwin セットアップ

```bash
# ✅ 1. nix-darwinインストール
nix run nix-darwin -- switch --flake ~/.config/nix-darwin

# ✅ 2. 初期設定確認
darwin-rebuild --version

# ✅ 3. システム統合テスト
sudo launchctl list | grep nix
```

#### Day 5-7: home-manager 統合

```bash
# ✅ 1. home-manager初期化
nix run home-manager/master -- init --switch

# ✅ 2. dotfiles統合テスト
home-manager switch

# ✅ 3. 基本動作確認
home-manager generations
```

#### Day 8-14: 基本CLIツール移行

**移行優先度順:**

1. **Critical Tools** (即移行)
   ```nix
   environment.systemPackages = with pkgs; [
     git
     gh  
     jq
     ripgrep
     tree
     starship
   ];
   ```

2. **Development Core** (慎重移行)
   ```nix
   environment.systemPackages = with pkgs; [
     neovim
     tmux
     shellcheck
     make
   ];
   ```

3. **Python/Node** (検証重要)
   ```nix
   environment.systemPackages = with pkgs; [
     python312
     nodejs_20
     nodePackages.npm
   ];
   ```

#### 検証項目
- [ ] 基本コマンド動作確認
- [ ] PATH設定正常性
- [ ] 既存スクリプトとの互換性
- [ ] パフォーマンス測定

---

## 💻 Phase 2: 開発環境移行（Week 3-4）

### 📋 実行チェックリスト

#### Day 15-18: エディター環境移行

```bash
# ✅ 1. Neovim設定移行確認
nix-shell -p neovim --run "nvim --version"

# ✅ 2. VSCode nixpkgs確認
nix search nixpkgs vscode

# ✅ 3. 既存プラグイン動作確認
# Claude Code Neovim統合テスト
```

**移行対象エディター:**
- `neovim` + LazyNvim
- `vscode` または `vscodium`
- `zed` (available in nixpkgs?)

#### Day 19-21: 言語環境移行

**Python環境:**
```nix
# Global Python
environment.systemPackages = with pkgs; [
  python312
  python312Packages.pip
  python312Packages.virtualenv
];

# Project-specific (direnv + flake)
# shell.nix でプロジェクト別管理
```

**Node.js環境:**
```nix
environment.systemPackages = with pkgs; [
  nodejs_20
  nodePackages.npm
  nodePackages.yarn
];
```

#### Day 22-25: ビルドツール・コンテナ

**検証必須項目:**
- [ ] Docker Desktop vs Podman vs nix コンテナ
- [ ] 既存プロジェクトビルド確認
- [ ] CI/CD互換性確認

```bash
# ✅ Docker環境選択
# Option A: Docker Desktop継続（Homebrew）
# Option B: nixpkgs docker + compose
# Option C: Podman完全移行

# ✅ ビルドツール確認
nix-shell -p gnumake cmake --run "make --version"
```

#### 緊急復旧計画
```bash
# 開発環境が破損した場合
brew install neovim git gh  # 最小限復旧
```

---

## 🖥️ Phase 3: システムツール移行（Week 5）

### ⚠️ 高リスクフェーズ

**重要**: このフェーズは慎重に実行し、各ステップで動作確認

#### Day 29-31: Yabaiエコシステム検証

```bash
# ✅ 1. nixpkgsでの対応状況確認
nix search nixpkgs yabai
nix search nixpkgs skhd  
nix search nixpkgs sketchybar

# ✅ 2. 代替手段調査
# yabai: koekeishiya/yabai (Homebrew継続の可能性)
# skhd: koekeishiya/skhd
# sketchybar: felixkratz/sketchybar
```

**戦略選択:**
- **Option A**: nixpkgs利用（推奨）
- **Option B**: Homebrew併用（安全策）
- **Option C**: Source Build（上級者向け）

#### Day 32-33: ターミナル環境移行

```nix
environment.systemPackages = with pkgs; [
  wezterm     # ターミナルエミュレータ
  tmux        # セッション管理
  starship    # プロンプト（Phase1で移行済み）
];
```

**検証項目:**
- [ ] Wezterm設定互換性
- [ ] tmux設定動作確認
- [ ] Claude Code統合確認

#### Day 34-35: サービス移行

```bash
# ✅ sketchybar サービス移行
# Homebrew LaunchAgent → nix-darwin launchd

# 現在の設定バックアップ
cp ~/Library/LaunchAgents/homebrew.mxcl.sketchybar.plist ~/backups/

# nix-darwin設定移行
# darwin.nix での launchd.agents 設定
```

---

## 🧹 Phase 4: 最適化・クリーンアップ（Week 6）

### 📋 実行チェックリスト

#### Day 36-38: 動作確認期間

```bash
# ✅ 全機能統合テスト
# 1. 開発環境での1日作業
# 2. システムツール動作確認
# 3. パフォーマンス測定

# 測定項目
time nix-shell -p hello --run "hello"  # nix起動速度
system_profiler SPSoftwareDataType     # システム情報
```

#### Day 39-41: Homebrew段階的削除

```bash
# ✅ 1. 削除対象パッケージ特定
comm -23 <(brew list --formula | sort) <(nixpkgs_packages | sort) > to_remove.txt

# ✅ 2. 依存関係チェック
brew deps --tree $(cat to_remove.txt) > deps_check.txt

# ✅ 3. 段階的削除実行
for pkg in $(cat to_remove.txt); do
  brew uninstall --ignore-dependencies $pkg
  # 動作確認後、次のパッケージ
done
```

#### Day 42: 最終確認・最適化

```bash
# ✅ 1. nix store最適化
nix store gc
nix store optimise

# ✅ 2. 設定ファイル整理
# 不要な設定ファイル削除
# flake.lock 最新化

# ✅ 3. ドキュメント更新
# README.md
# 新しい使用方法記載
```

---

## 🚨 各フェーズ共通: 緊急復旧手順

### 即座復旧コマンド
```bash
# 1. Homebrew環境復旧
brew bundle install --file=Brewfile.backup

# 2. nix無効化（必要時）
sudo launchctl unload /Library/LaunchDaemons/org.nixos.nix-daemon.plist

# 3. 設定ロールバック
git checkout HEAD~1 configs/
./install.sh --force
```

### 段階的復旧手順
```bash
# Phase別復旧
case $PHASE in
  1) brew install git gh jq ripgrep tree ;;
  2) brew install neovim python node ;;
  3) brew install yabai skhd sketchybar wezterm ;;
  *) brew bundle install --file=Brewfile.backup ;;
esac
```

---

## 📊 各フェーズ完了条件

### Phase 1 完了判定
- [ ] nix, nix-darwin, home-manager 正常インストール
- [ ] 基本CLIツール nix経由で利用可能
- [ ] 既存dotfilesとの統合完了
- [ ] パフォーマンス問題なし

### Phase 2 完了判定  
- [ ] 全開発プロジェクトでnix環境ビルド成功
- [ ] エディター・言語環境正常動作
- [ ] CI/CD互換性確認済み

### Phase 3 完了判定
- [ ] Yabai・skhd・sketchybar nix経由動作
- [ ] システムサービス正常起動
- [ ] 既存キーボードショートカット動作

### Phase 4 完了判定
- [ ] Homebrew依存パッケージ0個
- [ ] nix環境のみで全タスク実行可能
- [ ] 設定管理完全nix化

この段階的プランにより、リスクを最小化しながら確実にnix環境へ移行できます。