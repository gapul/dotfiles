# macOS ユーザー名変更ガイド（簡潔版）

**目的**: macOSのユーザー名「Yuki」を「yuki」に変更し、Nix $HOME ownership warningを解決

## 🎯 現在の状況（2025年6月20日確認済み）

- **ユーザー名**: Yuki（大文字Y）← これを変更
- **ホームディレクトリ**: /Users/yuki（小文字y）← 既に正しい
- **問題**: ユーザー名とディレクトリ名の不一致によるownership警告

## ⚠️ 事前準備（必須）

1. **Time Machineバックアップ実行**
2. **重要ファイル確認**（SSH鍵は `/Users/yuki/.ssh/` に既存確認済み）
3. **作業時間確保**（30分程度）

## 🚀 実行手順

### Step 1: 一時管理者ユーザー作成

**システム設定** > **ユーザとグループ** > **編集** > **ユーザまたはグループを追加**
- 種類: 管理者
- 氏名: Temporary Admin  
- アカウント名: tempAdmin
- パスワード: （強力なパスワード設定）

### Step 2: tempAdminでログイン

1. Yukiユーザーからログアウト
2. tempAdminでログイン

### Step 3: ユーザー名変更実行

```bash
# Directory Servicesのレコード名変更（メイン作業）
sudo dscl . -change /Users/Yuki RecordName Yuki yuki

# 権限修正
sudo chown -R yuki:staff /Users/yuki

# SSH権限確認
sudo chmod 700 /Users/yuki/.ssh
sudo chmod 600 /Users/yuki/.ssh/id_*
sudo chmod 644 /Users/yuki/.ssh/*.pub
```

### Step 4: 再起動・テスト

```bash
sudo reboot
```

再起動後、**yuki**ユーザーでログインして確認：

```bash
# 確認コマンド
whoami          # "yuki" と表示されること
pwd             # "/Users/yuki" と表示されること
id              # uid=501(yuki) と表示されること

# Nix設定テスト
cd /Users/yuki/dotfiles/nix
nix flake check --impure
```

### Step 5: クリーンアップ

**システム設定** > **ユーザとグループ** > **編集** > tempAdminユーザーを削除

## ✅ 完了確認

- [ ] `whoami` が "yuki" を返す
- [ ] Nix設定が警告なしで動作する
- [ ] SSH接続が正常に動作する

---

## 🔧 トラブルシューティング

**ログインできない場合**:
- Command + S でSingle User Mode起動
- `chmod -R u+rwX /Users/yuki && chown -R yuki:staff /Users/yuki`

**元に戻す場合**:
```bash
sudo dscl . -change /Users/yuki RecordName yuki Yuki
```

---

**更新**: 2025年6月20日（macOS 15.5対応）  
**リスク**: 低（レコード名変更のみ、ディレクトリ移動なし）  
**所要時間**: 約30分