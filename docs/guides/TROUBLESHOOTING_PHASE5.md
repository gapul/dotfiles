# 🔧 Phase 5 トラブルシューティングガイド

## エイリアス競合解決プロセス

### 🚨 発生した問題

Phase 5 Modern CLI Integration実装時に複数のエイリアス競合エラーが発生：

```
error: The option `home-manager.users.yuki.programs.zsh.shellAliases.cat' has conflicting definition values:
- In `<unknown-file>': "bat"
- In `modern-cli.nix': "bat --style=auto"
```

### 🔍 根本原因分析

**競合箇所の特定**:
1. `flake.nix:173` - `cat = "bat";`
2. `common/home/shell.nix:23` - `cat = "cat";`  
3. `common/tools/modern-cli.nix:72` - `cat = "bat --style=auto";`
4. `codespaces/default.nix:193` - `cat = "bat --style=auto";`

### 📋 解決ステップ

#### Step 1: 競合エイリアス特定
```bash
rg "cat.*=.*bat" nix/
rg "du.*=" nix/
rg "ls.*=" nix/
```

#### Step 2: 統一管理方針決定
- **modern-cli.nix**: メイン管理モジュール
- **flake.nix**: 汎用エイリアスを削除
- **shell.nix**: 基本エイリアスを削除
- **codespaces**: プラットフォーム固有設定は維持

#### Step 3: 段階的修正実行

**1. cat エイリアス修正**
```nix
# flake.nix
- cat = "bat";
+ # cat エイリアスはmodern-cli.nixで管理

# shell.nix  
- cat = "cat";
+ # cat エイリアスはmodern-cli.nixで管理
```

**2. 他の競合エイリアス修正**
```nix
# 以下をコメントアウト
- ls = "eza --icons";
- ll = "eza -la --icons --git";
- du = "dust";
- grep = "rg";
- find = "fd";
- top = "btm";
- df = "duf";
```

**3. modern-cli.nixで統一管理**
```nix
shellAliases = {
  ls = mkIf cfg.core-replacements "eza --color=auto --icons --group-directories-first";
  ll = mkIf cfg.core-replacements "eza -la --color=auto --icons --group-directories-first --git";
  la = mkIf cfg.core-replacements "eza -la --color=auto --icons --group-directories-first --git";
  cat = mkIf cfg.core-replacements "bat --style=auto";
  # ... 他のエイリアス
};
```

### 🛠️ 他の技術的修正

#### Deprecation警告対応
```nix
# modern-cli.nix
- initExtra = mkIf cfg.navigation ''
+ initContent = mkIf cfg.navigation ''
```

#### パッケージ名修正
```nix
# modern-cli.nix line 62
- (mkIf (cfg.git-ui && isDarwin) git-delta)
+ (mkIf (cfg.git-ui && isDarwin) delta)
```

### 📊 解決結果

**修正前**: 8個のエイリアス競合エラー
**修正後**: ✅ 全競合解消、統一管理実現

---

## 🚀 一般的なトラブルシューティング

### 1. nix-darwin適用エラー

#### 問題
```
sudo: a terminal is required to read the password
```

#### 解決策
```bash
# 必ずインタラクティブターミナルで実行
sudo nix run nix-darwin -- switch --flake .
```

### 2. エイリアスが適用されない

#### 問題
新しいエイリアスが効かない

#### 解決策
```bash
# シェル再起動
exec zsh

# または設定リロード
source ~/.zshrc

# Home Manager再適用
home-manager switch
```

### 3. ツールが見つからない

#### 問題
```bash
command not found: eza
```

#### 診断
```bash
# インストール確認
nix profile list | grep eza
which eza

# パス確認
echo $PATH
```

#### 解決策
```bash
# 設定再適用
sudo nix run nix-darwin -- switch --flake .

# 強制再インストール
nix profile remove <package>
nix profile install nixpkgs#eza
```

### 4. Neovim統合が動かない

#### 問題
キーバインドが効かない、プラグインエラー

#### 診断
```bash
nvim -c "checkhealth"
nvim --version
```

#### 解決策
```bash
# プラグイン状態確認
nvim -c "Lazy"

# 設定リロード
nvim -c "source ~/.config/nvim/init.lua"
```

### 5. zoxide学習しない

#### 問題
`z` コマンドで移動できない

#### 診断
```bash
# データベース確認
zoxide query --list
echo $ZOXIDE_DATA_DIR

# 初期化確認
which zoxide
```

#### 解決策
```bash
# 手動初期化
eval "$(zoxide init zsh)"

# データベース追加
zoxide add /path/to/directory

# 設定確認
grep -r "zoxide" ~/.zshrc
```

---

## 🔍 デバッグコマンド集

### Nix関連
```bash
# 設定検証
nix flake check
nix flake show

# ビルドログ確認
nix log /nix/store/[derivation]

# キャッシュクリア
nix store gc
nix flake check --refresh
```

### Home Manager関連
```bash
# 世代確認
home-manager generations

# 設定確認
home-manager option search programs.zsh

# 強制適用
home-manager switch --flake .
```

### Shell環境確認
```bash
# エイリアス一覧
alias

# 環境変数確認
env | grep -E "(ZOXIDE|EZA|RIPGREP)"

# シェル起動時間測定
time zsh -i -c exit
```

---

## 📞 サポート情報

### ログファイル確認
```bash
# nix-darwin ログ
journalctl -u nix-daemon

# Home Manager ログ  
cat ~/.local/state/home-manager/logs/
```

### 設定バックアップ
```bash
# Git履歴確認
git log --oneline | head -10

# 前の状態に戻す
git checkout HEAD~1 -- nix/common/tools/modern-cli.nix
```

### コミュニティサポート
- [NixOS Discourse](https://discourse.nixos.org/)
- [Nix Community Discord](https://discord.gg/RbvHtGa)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)

---

*このガイドにより、Phase 5実装時に発生する可能性のある問題を迅速に解決できます。*