# ⚡ Modern CLI Tools - クイックスタートガイド

## 🚀 5分で始める新しいターミナル体験

### 📋 準備完了チェック

以下のコマンドで準備状況を確認：

```bash
# Phase 5が適用されているか確認
./POST_INSTALLATION_CHECK.sh

# 新しいシェルセッション開始
exec zsh
```

---

## 🎯 今すぐ試せる！ Modern CLI体験

### 1. 📁 美しいファイル一覧 (eza)

```bash
# 従来: ls -la
ls -la    # 🎨 カラフル・アイコン付き・Git情報表示

# バリエーション
ll        # 詳細表示
la        # 隠しファイル含む詳細表示  
lt        # ツリー表示
```

**何が変わった？**
- 🎨 カラフルな表示
- 📂 ファイルタイプアイコン
- 📊 Git ステータス表示
- 📅 より読みやすい日付形式

### 2. 📄 シンタックスハイライト表示 (bat)

```bash
# 従来: cat README.md
cat README.md    # 🌈 シンタックスハイライト付き

# 便利な機能
cat config.json  # JSON自動認識
cat script.sh    # Shell script自動認識
```

**何が変わった？**
- 🌈 言語別シンタックスハイライト
- 📋 行番号表示
- 📝 Git差分表示
- 📑 ページング機能

### 3. 🔍 超高速検索 (ripgrep)

```bash
# 従来: grep -r "search term" .
grep "nix" .     # ⚡ 3-10倍高速

# パワフルな検索
rg "function.*test" --type ts    # TypeScriptファイルのみ
rg "TODO|FIXME" --ignore-case    # 大文字小文字無視
```

**何が変わった？**
- ⚡ 圧倒的な高速化
- 🧠 スマートな除外設定
- 🎨 美しい結果表示
- 📁 ファイルタイプ別検索

### 4. 🎯 直感的ファイル検索 (fd)

```bash
# 従来: find . -name "*.lua" -type f
find . -name "*.lua"    # 🔍 シンプル&高速

# 便利な使い方
fd config               # ファイル名検索
fd -e lua               # 拡張子指定
fd -t d project         # ディレクトリのみ
```

**何が変わった？**
- 🎯 直感的なシンタックス
- ⚡ 高速検索
- 🔍 スマートな除外
- 📁 パターンマッチング改善

---

## 🧠 スマートナビゲーション (zoxide)

### 学習型ディレクトリ移動

```bash
# 従来: cd /Users/yuki/dotfiles/nix/common
z dotfiles    # 🧠 学習した履歴から推測

# 使い方
z dev         # ~/Devに移動（使用頻度が高い場合）
z config      # 設定ディレクトリに移動
zi            # 🎯 インタラクティブ選択
```

**学習のコツ**:
1. 普通に`cd`で移動する
2. 数回使うとzoxideが学習
3. `z`で短縮移動が可能に

---

## 🎮 TUIツール体験

### 1. 🔥 LazyGit - Git操作革命

```bash
# 起動
lazygit

# または Neovim内で
# <leader>gg
```

**基本操作**:
- `j/k`: 上下移動
- `<space>`: ステージング
- `c`: コミット
- `P`: プッシュ
- `q`: 終了

### 2. 📁 Yazi - モダンファイルマネージャー

```bash
# 起動
yazi

# または Neovim内で  
# <leader>fm
```

**基本操作**:
- `j/k`: 上下移動
- `l`: 開く/Enter
- `h`: 戻る
- `space`: 選択
- `q`: 終了

### 3. 📊 Bottom - 美しいシステムモニター

```bash
# 起動
btm
# または
bottom

# または Neovim内で
# <leader>tm
```

**基本操作**:
- `c`: CPU
- `m`: メモリ
- `n`: ネットワーク
- `q`: 終了

---

## 🎯 Neovim統合キーバインド

### Phase 5専用キーバインド

```vim
<leader>gg    " LazyGit (フロート表示)
<leader>fm    " Yazi ファイルマネージャー
<leader>tm    " Bottom システムモニター
<leader>ff    " Telescope ファイル検索 (fd使用)
<leader>fg    " Telescope テキスト検索 (rg使用)
<leader>ft    " ファイルツリー表示 (eza使用)
<leader>bp    " カーソル下ファイルをbatでプレビュー
<leader>z     " Zoxide スマートジャンプ
<C-\>         " Toggleterm (フロートターミナル)
```

### 使用例

```vim
" ファイル検索 (超高速)
<leader>ff

" プロジェクト内文字列検索
<leader>fg

" Git操作
<leader>gg

" ファイル管理
<leader>fm
```

---

## 💡 生産性向上のコツ

### 1. エイリアス活用

```bash
# 日常的によく使うパターン
ls -la        # ファイル一覧確認
cat config    # 設定ファイル確認
grep TODO .   # TODOコメント検索
fd test       # テストファイル検索
```

### 2. zoxide学習促進

```bash
# よく使うディレクトリへの移動を繰り返す
cd ~/dotfiles && cd ~/Dev && cd ~/Documents
# 数回後...
z dot && z dev && z doc  # 短縮移動可能
```

### 3. TUIツールのワークフロー統合

```bash
# Git作業フロー
yazi          # ファイル選択
lazygit       # ステージング・コミット
btm           # システム負荷確認
```

---

## 🔧 カスタマイズヒント

### プロファイル変更

```nix
# nix/common/development/default.nix
modern-cli = {
  enable = true;
  profile = "full";  # minimal/standard/full
};
```

### 追加エイリアス

```nix
# modern-cli.nix shellAliases に追加
myalias = "your-command";
```

---

## 📊 効果確認

### パフォーマンス体感

```bash
# 前後比較テスト
time find . -name "*.nix"     # 従来
time fd "*.nix"               # Modern CLI

time grep -r "config" .       # 従来  
time rg "config"              # Modern CLI
```

### 視覚的改善確認

```bash
# 従来 vs Modern
/bin/ls -la    # vs    ls -la
/bin/cat file  # vs    cat file
```

---

## 🎉 習得完了の目安

### 1週間後のチェックリスト

- [ ] `ls`, `cat`, `grep`, `find` が自然に使える
- [ ] `z` でのディレクトリ移動が習慣化
- [ ] LazyGitでGit操作が快適
- [ ] Yaziでファイル操作が効率的
- [ ] Neovimキーバインドが身についている

### 2週間後のマスター状態

- [ ] TUIツールが日常ワークフローに統合
- [ ] zoxideで90%以上の移動がカバー
- [ ] 検索・操作が従来の3倍高速
- [ ] 新しいツールの探索意欲向上

---

**🚀 準備完了！新しいターミナル体験を楽しんでください！**

*困ったときは `TROUBLESHOOTING_PHASE5.md` を参照*