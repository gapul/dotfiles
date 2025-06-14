# Wezterm コマンド補完ガイド

## 設定状況の確認

Weztermのコマンド補完が正しく設定されているかどうかを確認する方法です。

## 1. 基本的な確認方法

### シェル環境の確認
```bash
# 現在のシェルを確認
echo $0
# 結果: /bin/zsh であることを確認

# 現在のfpath設定を確認
echo $fpath
# 結果に /opt/homebrew/share/zsh/site-functions が含まれていることを確認
```

### 補完ファイルの存在確認
```bash
# Homebrew経由のwezterm補完ファイル確認
ls -la $(brew --prefix)/share/zsh/site-functions/ | grep wezterm
# 結果: _wezterm ファイルが存在することを確認

# 補完関数の読み込み確認
type _wezterm
# 結果: "_wezterm is an autoload shell function" と表示されることを確認
```

## 2. 実際の補完動作テスト

### ターミナルでの確認方法

1. **新しいターミナルセッションを開く**
   ```bash
   # 新しいタブまたはウィンドウで
   wezterm [Tab キーを2回押す]
   ```
   
   期待される結果：利用可能なサブコマンド一覧が表示される
   ```
   cli                imgcat            serial            start
   connect            ls-fonts          set-working-directory   ssh
   help               record            shell-completion
   ```

2. **特定のサブコマンドでの補完テスト**
   ```bash
   # CLI サブコマンドの補完
   wezterm cli [Tab キーを2回押す]
   
   # SSH サブコマンドの補完
   wezterm ssh [Tab キーを2回押す]
   ```

## 3. トラブルシューティング

### 問題: 補完が動作しない場合

#### Step 1: 補完システムの手動初期化
```bash
# 現在のセッションで手動初期化
autoload -U compinit
compinit

# 補完関数の確認
type _wezterm
```

#### Step 2: zshrcの設定確認
```bash
# 設定ファイルの確認
cat ~/.zshrc | grep -A10 -B5 "補完"

# 期待される内容:
# - fpath設定: fpath=($(brew --prefix)/share/zsh/site-functions $fpath)
# - compinit実行: autoload -Uz compinit && compinit
```

#### Step 3: 補完キャッシュのクリア
```bash
# 補完キャッシュを削除
rm -f ~/.zcompdump*

# 新しいターミナルセッションを開始
exec zsh
```

### 問題: 補完関数は存在するが動作しない場合

#### Step 1: zshのオプション確認
```bash
# 補完機能が有効化されているか確認
setopt | grep -i comp

# AUTO_LIST と BASH_AUTO_LIST が有効になっていることを確認
```

#### Step 2: 補完スタイルの確認
```bash
# 現在の補完スタイル設定を確認
zstyle -L ':completion:*'
```

## 4. 動作確認のチェックリスト

### ✅ 確認項目

- [ ] zshを使用している (`echo $0` で確認)
- [ ] Homebrewがインストールされている (`which brew`)
- [ ] weztermがインストールされている (`which wezterm`)
- [ ] fpath に Homebrew の補完ディレクトリが含まれている
- [ ] _wezterm 補完関数が読み込まれている (`type _wezterm`)
- [ ] 新しいターミナルで `wezterm [Tab]` が動作する

### 🔧 修復手順

上記のいずれかが動作しない場合：

1. **zshrc再読み込み**
   ```bash
   source ~/.zshrc
   ```

2. **完全なターミナル再起動**
   - ターミナルアプリケーションを完全終了
   - 再度起動して確認

3. **手動での補完関数読み込み**
   ```bash
   autoload -U compinit && compinit -D
   ```

## 5. 高度な確認方法

### デバッグモードでの確認
```bash
# zsh デバッグモードで補完を確認
zsh -x -c 'autoload -U compinit; compinit; _wezterm'
```

### 補完候補の直接確認
```bash
# プログラム的に補完候補を取得
zsh -c '
autoload -U compinit; compinit
words=(wezterm "")
CURRENT=2
_wezterm
print -l $reply
'
```

## まとめ

Weztermの補完は正しく設定されています。新しいターミナルセッションで `wezterm [Tab]` を実行することで動作を確認できます。

問題が発生した場合は、上記のトラブルシューティング手順に従って解決してください。