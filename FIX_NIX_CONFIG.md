# 🔧 Nix設定修正手順

**問題**: `parallel-shell-jobs`設定が不明で、darwin-rebuildが失敗

**解決方法**: 以下のコマンドを順番に実行してください。

---

## 📋 実行すべきコマンド

### 1. nix.confの修正
```bash
# 問題のある設定をコメントアウト
sudo sed -i '' 's/parallel-shell-jobs = 4/# parallel-shell-jobs = 4  # Disabled - unknown setting/' /etc/nix/nix.conf

# 修正結果の確認
cat /etc/nix/nix.conf
```

### 2. darwin-rebuild再実行
```bash
cd ~/dotfiles
USER=yuki sudo darwin-rebuild switch --flake ~/.config/nix-darwin
```

---

## 🔍 現在の状況

### 修正済み
- ✅ flake.lockファイル更新完了
- ✅ nix設定でexperimental-featuresを有効化
- ✅ darwin.nixでnix.enable設定を修正

### 残っている問題
- ❌ `/etc/nix/nix.conf`の`parallel-shell-jobs = 4`設定

---

## 📝 修正後の期待される動作

1. **警告の解消**: `unknown setting 'parallel-shell-jobs'`警告がなくなる
2. **flake評価成功**: nix-darwinの設定が正常に評価される
3. **アプリインストール**: 40個のアプリケーションがnix管理下に移行

---

## 🚨 トラブルシューティング

### もし他のエラーが出た場合
```bash
# デバッグ情報を表示
USER=yuki sudo darwin-rebuild switch --flake ~/.config/nix-darwin --show-trace

# flake構文チェック
nix flake check ~/.config/nix-darwin

# 権限問題の場合
sudo chown -R $(whoami) /nix/var/nix/profiles/per-user/$(whoami)
```

### キャッシュクリア（最後の手段）
```bash
nix-collect-garbage -d
sudo nix-collect-garbage -d
```

---

**上記のコマンドを実行後、darwin-rebuildを再試行してください。**