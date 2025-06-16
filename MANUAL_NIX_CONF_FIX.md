# 🛠️ 手動でnix.conf修正が必要

**問題**: sudoとsedコマンドでnix.confの自動修正ができない

---

## 📋 手動修正手順

### 1. エディタでnix.confを開く
```bash
sudo nano /etc/nix/nix.conf
# または
sudo vim /etc/nix/nix.conf
```

### 2. 以下の行を見つけて修正
**変更前:**
```
restrict-eval = true
```

**変更後:**
```
# restrict-eval = true  # Disabled for flake builds
```

### 3. ファイルを保存して閉じる
- **nano**: `Ctrl+X` → `Y` → `Enter`
- **vim**: `:wq` → `Enter`

---

## 🚀 修正後の実行手順

### 4. Nixデーモン再起動（既に実行済み）
```bash
sudo launchctl stop org.nixos.nix-daemon
sudo launchctl start org.nixos.nix-daemon
```

### 5. darwin-rebuild実行
```bash
cd ~/dotfiles/nix
USER=yuki sudo darwin-rebuild switch --flake .
```

---

## 📝 修正内容の確認

修正後、以下で確認：
```bash
grep "restrict-eval" /etc/nix/nix.conf
```

**期待される出力:**
```
# restrict-eval = true  # Disabled for flake builds
```

---

## 🎯 代替案: 一時的無効化

もし完全コメントアウトが不安な場合：
```
restrict-eval = false
```

この設定でも動作し、後で`true`に戻すことができます。

---

## ⚠️ 重要な注意

### セキュリティについて
- `restrict-eval`はnixのセキュリティ機能
- flake使用時は通常安全に無効化可能
- システム管理目的のみに使用

### トラブルシューティング
もし修正後もエラーが発生する場合：
```bash
# flake.lock再生成
cd ~/dotfiles/nix
rm -f flake.lock
nix flake lock
USER=yuki sudo darwin-rebuild switch --flake .
```

---

## 🎉 成功後の期待結果

- **48個のGUIアプリケーション**がnix管理下に移行
- **DaVinci Resolve**: プロ動画編集環境
- **Steam + ゲーム**: 完全なゲーミング環境  
- **開発ツール**: VS Code, WezTerm等
- **実行時間**: 30-50分

---

**上記の手順でnix.confを修正後、darwin-rebuildを再実行してください！**