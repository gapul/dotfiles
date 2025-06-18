# macOS ユーザー名変更ガイド

このドキュメントは、macOSのユーザー名を「Yuki」から「yuki」に変更する手順を説明します。

## 目的

- $HOME ownership warning の根本的解決
- Unix/Linux系システムとの一貫性確保
- 開発ツール（Nix、Docker、SSH等）との互換性向上
- クロスプラットフォーム対応の改善

## 現在の問題

```bash
# 現在発生している警告
warning: $HOME ('/Users/yuki') is not owned by you, falling back to the one defined in the 'passwd' file ('/var/root')
```

**原因：**
- macOSの実際のユーザー名：「Yuki」（大文字Y）
- Nixの設定で使用している名前：「yuki」（小文字y）
- ディレクトリの所有者と実行ユーザーの不一致

## ⚠️ 重要な注意事項

**必須の準備作業：**
- [ ] **完全バックアップの作成** - Time Machineまたは手動バックアップ
- [ ] **重要なファイルの場所確認** - SSH鍵、GPG鍵、アプリケーション設定
- [ ] **作業時間の確保** - 30分〜1時間程度
- [ ] **外部ストレージの準備** - バックアップ用

**リスク：**
- アプリケーションの再設定が必要になる場合がある
- FileVault暗号化が有効な場合、追加手順が必要
- 一部のライセンス認証のやり直しが必要な場合がある

## 手順

### Phase 1: 準備作業

#### 1.1 バックアップの作成

```bash
# Time Machineバックアップを実行
sudo tmutil startbackup

# または手動バックアップ（推奨：両方実行）
sudo rsync -av /Users/Yuki/ /Volumes/外部ドライブ/backup_Yuki_$(date +%Y%m%d_%H%M%S)/
```

#### 1.2 重要なファイルの確認

```bash
# SSH鍵の確認
ls -la ~/.ssh/
echo "SSH鍵の場所: $(ls ~/.ssh/id_* 2>/dev/null || echo 'なし')"

# GPG鍵の確認
ls -la ~/.gnupg/ 2>/dev/null || echo "GPG設定なし"

# アプリケーション設定の確認
ls -la ~/Library/Application\ Support/ | head -10

# 開発環境の確認
which nix && echo "Nix installed: $(nix --version)"
which brew && echo "Homebrew installed: $(brew --version | head -1)"
ls -la ~/.gitconfig 2>/dev/null && echo "Git設定あり"
```

#### 1.3 現在のユーザー情報の記録

```bash
# 現在の設定を記録
whoami > ~/Desktop/current_user_info.txt
id >> ~/Desktop/current_user_info.txt
pwd >> ~/Desktop/current_user_info.txt
ls -la /Users/ >> ~/Desktop/current_user_info.txt
sudo dscl . -read /Users/Yuki >> ~/Desktop/current_user_info.txt
```

### Phase 2: 一時管理者ユーザーの作成

#### 2.1 管理者ユーザーの作成

**GUI操作：**
1. **システム設定** > **ユーザとグループ** を開く
2. 左下の **鍵アイコン** をクリックして認証
3. **+** ボタンをクリック
4. 以下の設定で新規ユーザーを作成：
   - **新規アカウント**: 管理者
   - **氏名**: `Temporary Admin`
   - **アカウント名**: `tempAdmin`
   - **パスワード**: 強力なパスワードを設定
   - **パスワードの確認**: 同じパスワード
5. **ユーザを作成** をクリック

#### 2.2 tempAdminでのログイン

1. 現在のYukiユーザーからログアウト
2. tempAdminでログイン
3. ターミナルを開く

### Phase 3: ユーザー名変更の実行

#### 3.1 事前確認

```bash
# tempAdminとしてログインしていることを確認
whoami  # "tempAdmin" と表示されることを確認

# Yukiユーザーがログアウトしていることを確認
who

# 現在のユーザー一覧を確認
sudo dscl . -list /Users | grep -v "^_"
```

#### 3.2 ユーザー名変更の実行

```bash
# 1. Yukiユーザーの現在の設定を確認・保存
sudo dscl . -read /Users/Yuki > ~/Desktop/yuki_user_backup.txt

# 2. ユーザー名の変更（慎重に実行）
echo "ホームディレクトリの変更..."
sudo dscl . -change /Users/Yuki NFSHomeDirectory /Users/Yuki /Users/yuki

echo "レコード名の変更..."
sudo dscl . -change /Users/Yuki RecordName Yuki yuki

# 3. 実際のホームディレクトリ名を変更
echo "ディレクトリ名の変更..."
sudo mv /Users/Yuki /Users/yuki

# 4. 所有者とアクセス権限の修正
echo "所有者の変更..."
sudo chown -R yuki:staff /Users/yuki

echo "アクセス権限の修正..."
sudo chmod -R u+rwX /Users/yuki
```

#### 3.3 変更の確認

```bash
# 変更後の設定を確認
sudo dscl . -read /Users/yuki > ~/Desktop/yuki_user_after.txt

# ディレクトリの確認
ls -la /Users/ | grep yuki

# 所有者の確認
ls -ld /Users/yuki
```

### Phase 4: システムの再起動とテスト

#### 4.1 システム再起動

```bash
# 設定を保存してシステム再起動
sudo reboot
```

#### 4.2 yukiユーザーでのログインテスト

1. 再起動後、**yuki** ユーザーでログイン
2. ターミナルを開いて確認：

```bash
# ユーザー名の確認
whoami  # "yuki" と表示されることを確認

# ホームディレクトリの確認
pwd     # "/Users/yuki" と表示されることを確認

# ユーザーIDの確認
id      # uid=501(yuki) のように表示されることを確認

# ファイルアクセスの確認
ls -la ~/
touch ~/test_file && rm ~/test_file && echo "ファイル作成OK"
```

### Phase 5: アプリケーションと設定の修復

#### 5.1 基本的なアクセス権限の修復

```bash
# ホームディレクトリの完全な権限修復
sudo chown -R yuki:staff /Users/yuki
sudo chmod -R u+rwX /Users/yuki

# 隠しファイルの権限確認
ls -la ~/.*
```

#### 5.2 開発環境の修復

```bash
# SSH設定の修復
if [ -d ~/.ssh ]; then
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/id_* 2>/dev/null || true
    chmod 644 ~/.ssh/*.pub 2>/dev/null || true
    echo "SSH権限修復完了"
fi

# Homebrew権限の修復（存在する場合）
if [ -d /opt/homebrew ]; then
    sudo chown -R yuki:staff /opt/homebrew
    echo "Homebrew権限修復完了"
fi

# Nix設定の確認
if command -v nix >/dev/null 2>&1; then
    echo "Nix version: $(nix --version)"
    echo "Nix設定確認OK"
fi
```

#### 5.3 Git設定の確認

```bash
# Git設定の確認
git config --global user.name
git config --global user.email

# 必要に応じて再設定
# git config --global user.name "Your Name"
# git config --global user.email "your.email@example.com"
```

### Phase 6: Nix設定のテスト

#### 6.1 dotfiles設定の確認

```bash
# dotfilesディレクトリに移動
cd /Users/yuki/dotfiles

# 権限の確認
ls -la

# Nix設定のテスト
cd nix && nix flake check --no-build
```

#### 6.2 システム再構築のテスト

```bash
# $HOME ownership warningが解消されているかテスト
sudo nix run nix-darwin -- switch --flake .#default

# 警告が出力されないことを確認
# 期待される結果: "warning: $HOME ('/Users/yuki') is not owned by you" が表示されない
```

### Phase 7: クリーンアップ

#### 7.1 一時管理者の削除

**GUI操作：**
1. **システム設定** > **ユーザとグループ** を開く
2. tempAdminユーザーを選択
3. **-** ボタンをクリックして削除
4. **ホームフォルダを削除** を選択

#### 7.2 バックアップファイルの整理

```bash
# デスクトップの一時ファイルを整理
mkdir -p ~/Documents/username_change_backup
mv ~/Desktop/*user*.txt ~/Documents/username_change_backup/ 2>/dev/null || true
```

## Phase 8: 動作確認とアプリケーション再設定

### 8.1 基本動作の確認

```bash
# ファイルシステムアクセス
echo "File system test" > ~/test.txt && cat ~/test.txt && rm ~/test.txt

# ネットワークアクセス
ping -c 1 google.com

# 開発ツールの確認
which git && git --version
which nix && nix --version
```

### 8.2 再設定が必要なアプリケーション

以下のアプリケーションは再設定が必要な場合があります：

**開発ツール：**
- [ ] **Xcode** - Developer accountの再ログイン
- [ ] **VSCode/Cursor** - 設定同期の再有効化
- [ ] **SSH keys** - リモートサーバーへの接続確認
- [ ] **Git** - 認証情報の確認

**一般アプリケーション：**
- [ ] **Claude Code** - 設定の再確認
- [ ] **iCloud同期** - 必要に応じて再有効化
- [ ] **Adobe製品** - ライセンス認証の確認
- [ ] **Dropbox/Google Drive** - 同期フォルダの再設定

### 8.3 完了確認チェックリスト

- [ ] `whoami` が "yuki" を返す
- [ ] `pwd` が "/Users/yuki" を返す
- [ ] SSH接続が正常に動作する
- [ ] Git操作が正常に動作する
- [ ] Nix設定が警告なしで動作する
- [ ] 主要なアプリケーションが正常に起動する
- [ ] ファイルの読み書きが正常に動作する

## トラブルシューティング

### 問題が発生した場合の復旧手順

#### 方法1: Time Machineからの復元

```bash
# Time Machine復元の実行
# システム復元ユーティリティから Time Machine バックアップを選択
```

#### 方法2: Single User Modeでの修復

1. **Command + S** を押しながら起動
2. Single User Modeでコマンド実行：

```bash
# ファイルシステムの確認
/sbin/fsck -fy

# 読み書きでマウント
/sbin/mount -uw /

# ユーザー設定の確認
dscl . -list /Users

# 必要に応じて設定を戻す
dscl . -change /Users/yuki RecordName yuki Yuki
dscl . -change /Users/yuki NFSHomeDirectory /Users/yuki /Users/Yuki
mv /Users/yuki /Users/Yuki

# 再起動
reboot
```

#### 方法3: Recovery Modeでの修復

1. **Command + R** を押しながら起動
2. ターミナルユーティリティから修復作業を実行

### よくある問題と解決法

**問題1: ログインできない**
```bash
# 解決法: Single User Modeで権限修復
chmod -R u+rwX /Users/yuki
chown -R yuki:staff /Users/yuki
```

**問題2: アプリケーションが起動しない**
```bash
# 解決法: アプリケーション設定のリセット
rm -rf ~/Library/Caches/*
rm -rf ~/Library/Application\ Support/[問題のアプリ]/
```

**問題3: SSH接続ができない**
```bash
# 解決法: SSH設定の再生成
ssh-keygen -t ed25519 -C "your.email@example.com"
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
```

## 参考情報

### 作業前の確認コマンド

```bash
# 現在のユーザー情報を完全に記録
{
    echo "=== User Information ==="
    whoami
    id
    
    echo -e "\n=== Directory Information ==="
    pwd
    ls -la /Users/
    
    echo -e "\n=== System Information ==="
    sw_vers
    
    echo -e "\n=== Directory Services Information ==="
    sudo dscl . -read /Users/Yuki
    
    echo -e "\n=== Current Processes ==="
    ps aux | grep Yuki
    
    echo -e "\n=== File Ownership Sample ==="
    ls -la ~ | head -10
    
} > ~/Desktop/pre_change_system_info_$(date +%Y%m%d_%H%M%S).txt
```

### 作業後の確認コマンド

```bash
# 変更後の確認
{
    echo "=== Post-Change Verification ==="
    whoami
    id
    pwd
    
    echo -e "\n=== Directory Verification ==="
    ls -la /Users/ | grep yuki
    ls -ld /Users/yuki
    
    echo -e "\n=== Nix Test ==="
    cd /Users/yuki/dotfiles/nix
    nix flake check --no-build 2>&1
    
    echo -e "\n=== Home Ownership ==="
    ls -la /Users/yuki | head -5
    
} > ~/Desktop/post_change_verification_$(date +%Y%m%d_%H%M%S).txt
```

## まとめ

この手順により、macOSユーザー名を「Yuki」から「yuki」に変更し、$HOME ownership warningを根本的に解決できます。

**メリット：**
- Nix/home-manager の警告解消
- Unix/Linux系システムとの一貫性
- 開発ツールとの互換性向上
- 将来的なトラブルの予防

**注意：**
- 必ずバックアップを作成してから実行
- アプリケーションの再設定が必要な場合がある
- 作業時間を十分に確保する

---

**作成日**: 2025年6月18日  
**対象システム**: macOS (Apple Silicon/Intel)  
**対象ユーザー**: Yuki → yuki  
**関連**: Nix, home-manager, dotfiles管理