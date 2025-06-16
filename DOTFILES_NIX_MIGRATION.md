# 🔄 home-managerドットファイル管理移行ガイド

**作成日**: 2025年6月16日  
**目的**: シンボリックリンクベース管理からhome-manager宣言的管理への移行

---

## 📋 移行の概要

### 現在の状況
- **シンボリックリンク**: install.sh によるマニュアル管理
- **home-manager**: 部分的に設定済み（zsh管理済み）
- **ハイブリッド状態**: 一部ファイルがhome-manager管理

### 移行後の構成
- **✅ 宣言的管理**: home.nix で完全にドットファイル定義
- **✅ 統合管理**: プログラム設定とファイル配置の一元化
- **✅ 再現性**: git + nix による100%環境再現

---

## 🎯 移行対象ファイル

### Phase 1: ターミナル環境 (完全統合)
```nix
programs.starship = {
  enable = true;
  settings = import starship.toml;  # 既存設定を直接インポート
};

programs.tmux = {
  enable = true;
  extraConfig = readFile tmux.conf;  # 既存設定を直接インポート
};

programs.zsh = {
  enable = true;
  initExtraFirst = ''source existing-zshrc'';  # 既存設定統合
};
```

### Phase 2: エディター環境 (ファイル配置)
```nix
home.file = {
  ".config/nvim".source = "configs/editors/nvim";
  ".config/Code/User/settings.json".source = "configs/editors/vscode/settings.json";
  ".config/zed/settings.json".source = "configs/editors/zed/settings.json";
};
```

### Phase 3: 開発ツール (ファイル配置)
```nix
home.file = {
  ".condarc".source = "configs/development/.condarc";
  ".docker/config.json".source = "configs/development/docker/config.json";
  ".config/gh/config.yml".source = "configs/cli/gh/config.yml";
};
```

### Phase 4: ウィンドウマネージャー (オプション)
```nix
home.file = {
  # ".config/yabai/yabairc".source = "configs/wm/yabai/yabairc";  # コメントアウト済み
  # ".config/skhd/skhdrc".source = "configs/wm/skhd/skhdrc";      # 安全性重視
};
```

---

## 🔧 実装済み設定

### ターミナル統合管理
- **starship**: 既存のTOML設定を直接インポート
- **tmux**: 既存のconf設定を直接インポート  
- **zsh**: 既存のzshrcを最初に読み込み + home-managerエイリアス追加

### ファイル管理統合
- **エディター**: nvim, VSCode, Zed設定
- **開発ツール**: conda, docker, gh設定
- **アプリ設定**: Claude MCP設定（テンプレート）

### ショートカット統合
```bash
# nix管理コマンド
nrs      # darwin-rebuild switch
hms      # home-manager switch

# 従来のドットファイル管理（並行利用可能）
install       # install.sh
install-force # install.sh --force
backup-list   # バックアップ一覧
```

---

## 🚀 移行実行手順

### Step 1: 現在のシンボリックリンクを確認
```bash
ls -la ~ | grep '\->'
```

### Step 2: home-manager適用
```bash
cd ~/dotfiles/nix
home-manager switch --flake .
```

### Step 3: 動作確認
```bash
# starship設定確認
starship config

# tmux設定確認  
tmux show-options

# zsh設定確認
echo $SHELL
which starship
```

### Step 4: 競合解決（必要時）
```bash
# 既存シンボリックリンクのバックアップ
mv ~/.zshrc ~/.zshrc.backup
mv ~/.tmux.conf ~/.tmux.conf.backup

# home-manager再適用
home-manager switch --flake .
```

---

## 📊 メリット比較

### シンボリックリンク方式
- ✅ 理解しやすい
- ✅ 個別ファイル編集が簡単
- ❌ 手動管理が必要
- ❌ システム間での同期が複雑

### home-manager方式  
- ✅ 宣言的管理
- ✅ プログラム統合（starship, tmux等）
- ✅ 完全な再現性
- ✅ バージョン管理統合
- ❌ nix知識が必要
- ❌ 初期設定が複雑

---

## 🛡️ 安全対策

### バックアップ保持
- **既存システム**: install.sh によるバックアップ継続利用可能
- **home-manager**: 世代管理で自動ロールバック可能

### 段階的移行
1. **Phase 1**: ターミナル環境のみ（リスク最小）
2. **Phase 2**: エディター設定追加
3. **Phase 3**: 開発ツール設定追加
4. **Phase 4**: WM設定（オプション）

### ロールバック方法
```bash
# home-manager世代確認
home-manager generations

# 前の世代に戻す
home-manager switch --flake . --rollback

# または既存のinstall.shに戻す
~/dotfiles/install.sh --force
```

---

## 🎯 実行推奨

**現在の設定:**
- ✅ home.nix に完全なドットファイル管理設定完了
- ✅ 既存設定との統合設計完了
- ✅ 安全対策とロールバック方法準備完了

**次のステップ:**
```bash
cd ~/dotfiles/nix
home-manager switch --flake .
```

これで**宣言的ドットファイル管理**システムが完成します！

---

## 📝 注意事項

### セキュリティファイル除外
- `.gitconfig` (個人情報)
- `.ssh/config` (サーバー情報)  
- `claude.json` (ユーザーID)

### プログラム設定優先
starship, tmux, zsh等はhome-managerのプログラム設定機能を活用し、単純なファイルコピーより高機能な統合管理を実現。

### 互換性維持
既存のinstall.shシステムは並行利用可能。段階的移行やトラブル時のフォールバックとして活用。