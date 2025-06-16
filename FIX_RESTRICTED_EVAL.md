# 🔧 Restricted Eval 問題の解決

**根本原因発見**: `/etc/nix/nix.conf`の`restrict-eval = true`がflake実行を阻害

---

## 🎯 解決手順

### 1. nix.confの修正（必須）
```bash
# restrict-eval設定を無効化
sudo sed -i '' 's/restrict-eval = true/# restrict-eval = true  # Disabled for flake builds/' /etc/nix/nix.conf

# 修正結果の確認
grep "restrict-eval" /etc/nix/nix.conf
```

### 2. Nixデーモン再起動
```bash
# Nixデーモン再起動
sudo launchctl stop org.nixos.nix-daemon
sudo launchctl start org.nixos.nix-daemon
```

### 3. darwin-rebuild実行
```bash
cd ~/dotfiles/nix
USER=yuki sudo darwin-rebuild switch --flake .
```

---

## 📋 完全な実行コマンド（順番に実行）

```bash
# Step 1: nix.conf修正
sudo sed -i '' 's/restrict-eval = true/# restrict-eval = true  # Disabled for flake builds/' /etc/nix/nix.conf

# Step 2: Nixデーモン再起動
sudo launchctl stop org.nixos.nix-daemon
sudo launchctl start org.nixos.nix-daemon

# Step 3: darwin-rebuild実行
cd ~/dotfiles/nix
USER=yuki sudo darwin-rebuild switch --flake .
```

---

## 🔍 問題の説明

### 発見された設定問題
- **restrict-eval = true**: flakeのGitHub取得を禁止
- **Determinate Nix**: 標準のnix-channelが非推奨
- **sandbox = true**: 一部のビルドを制限

### 修正内容
```diff
# /etc/nix/nix.conf
- restrict-eval = true
+ # restrict-eval = true  # Disabled for flake builds
```

---

## ⚠️ 重要な注意

### セキュリティについて
- `restrict-eval`無効化は通常のflake使用には安全
- 信頼できないコードの実行は避ける
- システム管理者権限での実行のため注意深く操作

### 代替案（より安全）
もしセキュリティを優先する場合：
```bash
# 一時的に無効化
sudo sed -i '' 's/restrict-eval = true/restrict-eval = false/' /etc/nix/nix.conf

# darwin-rebuild実行後に再有効化
sudo sed -i '' 's/restrict-eval = false/restrict-eval = true/' /etc/nix/nix.conf
```

---

## 🎯 実行後の確認

### 成功の確認
```bash
# システム世代確認
darwin-rebuild --list-generations

# 新規インストールアプリ確認
ls /Applications | grep -E "(DaVinci|Steam|Visual Studio Code|Zrythm)"

# nix管理パッケージ数確認
nix-env --query --installed | wc -l
```

### 予想される結果
- **48個のGUIアプリケーション**がnix管理下に移行
- **DaVinci Resolve**: プロ動画編集環境
- **Steam + Minecraft**: ゲーミング環境
- **Zrythm**: プロ音楽制作環境
- **総実行時間**: 30-50分

---

## 🚨 トラブルシューティング

### もしまだエラーが発生する場合
```bash
# flake.lock削除して再生成
cd ~/dotfiles/nix
rm -f flake.lock
nix flake lock
USER=yuki sudo darwin-rebuild switch --flake .
```

### デバッグモード
```bash
# 詳細ログで実行
USER=yuki sudo darwin-rebuild switch --flake . --show-trace -v
```

---

**上記の手順を順番に実行してください。48個のプロフェッショナルアプリケーションのインストールが開始されます！**