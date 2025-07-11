# 実装ロードマップ: Modern CLI Integration Phase 5

## 🎯 全体戦略

**基本方針**: 既存の安定したシステムを维持しながら、段階的にモダンツールを統合
**期間**: 2-4週間での完全実装
**リスク管理**: 各ステップでロールバック可能な設計

---

## 📋 Step-by-Step Implementation Plan

### 🚀 **Step 1: Core Modern CLI Tools (Week 1 - Day 1-2)**
**優先度**: ⭐⭐⭐ **CRITICAL** - 即効性最高
**所要時間**: 2-4時間
**リスク**: 🟢 Low

#### 実行コマンド
```bash
# 1. 設定を適用
cd /Users/yuki/dotfiles
nix flake check  # 設定検証

# 2. Darwin設定を更新
sudo nix run nix-darwin -- switch --flake .

# 3. 動作確認
eza --version
bat --version
rg --version
fd --version
```

#### 期待効果
- `ls` → `eza`: カラフルなファイル一覧とGit情報表示
- `cat` → `bat`: シンタックスハイライト付きファイル表示
- `grep` → `rg`: 3-10倍高速なテキスト検索
- `find` → `fd`: 5-10倍高速なファイル検索

#### 確認テスト
```bash
# エイリアスが正しく設定されているか
alias ls
alias cat
alias grep
alias find

# ツールが動作するか
ls -la          # ezaで表示される
cat README.md   # batで表示される
grep "test" .   # rgで検索される
find . -name "*.nix"  # fdで検索される
```

---

### 🔧 **Step 2: Smart Navigation (Week 1 - Day 3-4)**
**優先度**: ⭐⭐⭐ **HIGH** - 劇的な効率化
**所要時間**: 1-2時間
**リスク**: 🟡 Medium (学習コスト)

#### 実行コマンド
```bash
# 設定有効化 (modern-cli.nixで既に設定済み)
# zoxideの初期化
z --help  # ヘルプ表示でインストール確認

# 使用開始
cd /Users/yuki/dotfiles
cd /Users/yuki/Dev
cd /Users/yuki
z dotfiles  # zoxideでスマートジャンプ
z dev       # 学習した履歴から推測
```

#### 期待効果
- **学習型ディレクトリ移動**: 使用履歴から最適なパスを推測
- **キーストローク削減**: `cd /very/long/path` → `z long`
- **生産性向上**: ディレクトリ移動時間50-80%短縮

---

### 🎨 **Step 3: Git & File Management UI (Week 1 - Day 5-7)**
**優先度**: ⭐⭐ **MEDIUM** - ワークフロー革新
**所要時間**: 2-3時間
**リスク**: 🟡 Medium (新しいUI)

#### 実行コマンド
```bash
# LazyGit起動テスト
lazygit  # Gitリポジトリ内で実行

# Yazi起動テスト  
yazi     # ファイルマネージャー起動

# Neovim統合テスト
nvim
# Neovim内で <leader>gg (LazyGit起動)
# Neovim内で <leader>fm (Yazi起動)
```

#### 期待効果
- **LazyGit**: 複雑なGit操作をTUIで直感的に
- **Yazi**: 高速ファイルブラウジングと画像プレビュー
- **Neovim統合**: エディタからシームレスなツール連携

#### カスタマイズポイント
```bash
# LazyGitの設定ファイル作成
mkdir -p ~/.config/lazygit
# Yaziのテーマ設定は既にnixで管理済み
```

---

### 📊 **Step 4: System Monitoring (Week 2 - Day 1-2)**
**優先度**: ⭐ **LOW** - 特定用途
**所要時間**: 30分-1時間
**リスク**: 🟢 Low

#### 実行コマンド
```bash
# Bottom起動テスト
btm      # 美しいシステムモニター
bottom   # 同じツール

# Neovim統合テスト
nvim
# <leader>tm でBottom起動
```

#### 期待効果
- **視覚的システム監視**: CPU、メモリ、ネットワークのグラフ表示
- **htop/top代替**: より現代的で情報豊富なインターフェース

---

### 🔍 **Step 5: Enhanced History (Week 2 - Day 3-5) - Optional**
**優先度**: ⭐ **OPTIONAL** - プライバシー考慮
**所要時間**: 1-2時間
**リスク**: 🟡 Medium (プライバシー設定)

#### 実行前の準備
```bash
# プライバシー設定の確認
# atuin sync を無効にするかローカルのみで使用するか決定
```

#### 実行コマンド
```bash
# atuinを有効化 (modern-cli.nixで設定)
modern-cli.history = true;

# 履歴インポート
atuin import auto

# 使用開始
# Ctrl+R でatuin検索インターフェース起動
```

---

### ⚡ **Step 6: Performance Optimization (Week 2 - Day 6-7)**
**優先度**: ⭐⭐ **MEDIUM** - システム最適化
**所要時間**: 1-2時間
**リスク**: 🟢 Low

#### 実行内容
```bash
# Nix store cleanup
nix store gc --verbose

# シェル起動時間測定
time zsh -i -c exit

# dotfiles全体のhealth check
dev-health
```

#### 期待効果
- **システムクリーンアップ**: 不要なNixパッケージ削除
- **起動時間最適化**: シェル起動時間の改善
- **設定統合確認**: 全ツールの正常動作確認

---

## 📈 成功指標と効果測定

### 定量的指標
- **ファイル検索時間**: `find` vs `fd` (目標: 5-10倍高速化)
- **テキスト検索時間**: `grep` vs `rg` (目標: 3-10倍高速化)
- **ディレクトリ移動**: 平均キーストローク数 (目標: 50%削減)
- **Git操作効率**: commit/push/pullの時間 (目標: 30%削減)

### 定性的指標
- **ユーザビリティ**: カラー表示とアイコンによる視認性向上
- **学習効果**: zoxideによる移動パターン学習
- **ワークフロー統合**: Neovimからのシームレスなツール起動

---

## 🔧 Troubleshooting Guide

### 一般的な問題と解決策

#### 1. **Nixビルドエラー**
```bash
# エラーログ確認
nix log /nix/store/[failed-derivation]

# キャッシュクリア
nix store gc
nix flake check --refresh
```

#### 2. **エイリアスが効かない**
```bash
# シェル設定リロード
source ~/.zshrc

# Home Manager設定確認
home-manager generations
```

#### 3. **Neovim統合が動かない**
```bash
# 必要プラグインの確認
nvim --version
nvim -c "checkhealth"

# toggleterm.nvimがインストールされているか確認
```

#### 4. **zoxideが学習しない**
```bash
# zoxide初期化確認
echo $ZOXIDE_DATA

# データベース確認
zoxide query --list
```

---

## 🎉 完了後の次のステップ

### Week 3-4: Advanced Integration
1. **tmux → zellij移行の検討**
2. **fastfetch設定のカスタマイズ**
3. **独自スクリプトの作成**
4. **他プロジェクトへの適用**

### 継続的改善
1. **定期的なツール更新**: `nix flake update`
2. **新ツールの評価**: コミュニティからの新しい推奨ツール
3. **設定の最適化**: 使用パターンに基づく継続的調整

---

## 📞 サポートリソース

### 公式ドキュメント
- [eza GitHub](https://github.com/eza-community/eza)
- [bat GitHub](https://github.com/sharkdp/bat)
- [ripgrep GitHub](https://github.com/BurntSushi/ripgrep)
- [fd GitHub](https://github.com/sharkdp/fd)
- [zoxide GitHub](https://github.com/ajeetdsouza/zoxide)
- [lazygit GitHub](https://github.com/jesseduffield/lazygit)
- [yazi GitHub](https://github.com/sxyazi/yazi)

### コミュニティ
- [r/NixOS](https://reddit.com/r/NixOS)
- [Nix Community Discord](https://discord.gg/RbvHtGa)
- [Modern Unix GitHub](https://github.com/ibraheemdev/modern-unix)

---

**準備完了！あなたのターミナル環境を次のレベルへ** 🚀