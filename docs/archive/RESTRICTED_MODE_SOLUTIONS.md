# 🔧 Restricted Mode 解決方法

**問題**: nix flakeがGitHubからnixpkgsを取得する際にrestricted modeエラー

---

## 🚀 解決方法 1: Nixデーモン再起動 + --impure

```bash
# Nixデーモン再起動
sudo launchctl stop org.nixos.nix-daemon
sudo launchctl start org.nixos.nix-daemon

# darwin-rebuild実行
cd ~/dotfiles/nix
USER=yuki sudo darwin-rebuild switch --flake . --impure
```

## 🚀 解決方法 2: 従来のnix-channel方式

```bash
# nix-channelでnixpkgsを設定
nix-channel --add https://github.com/NixOS/nixpkgs/archive/nixpkgs-unstable.tar.gz nixpkgs
nix-channel --update

# 従来方式でdarwin-rebuild
cd ~/dotfiles/nix
USER=yuki sudo darwin-rebuild switch -I darwin-config=./darwin.nix
```

## 🚀 解決方法 3: flake.lock削除 + 再生成

```bash
cd ~/dotfiles/nix
rm -f flake.lock
nix flake lock --extra-experimental-features 'nix-command flakes'
USER=yuki sudo darwin-rebuild switch --flake . --impure
```

## 🚀 解決方法 4: ローカルnixpkgs使用

```bash
# nixpkgsをローカルにクローン
cd ~/
git clone https://github.com/NixOS/nixpkgs.git
cd ~/dotfiles/nix

# ローカルパスでflake実行
USER=yuki sudo darwin-rebuild switch --override-input nixpkgs ~/nixpkgs --impure
```

## 🚀 解決方法 5: システム設定変更

```bash
# /etc/nix/nix.confに追加
echo "experimental-features = nix-command flakes" | sudo tee -a /etc/nix/nix.conf
echo "allow-import-from-derivation = true" | sudo tee -a /etc/nix/nix.conf

# darwin-rebuild再実行
cd ~/dotfiles/nix
USER=yuki sudo darwin-rebuild switch --flake . --impure
```

---

## 📋 推奨実行順序

1. **解決方法 1**: 最も簡単（Nixデーモン再起動）
2. **解決方法 3**: flake.lock再生成
3. **解決方法 2**: 従来方式（確実に動作）
4. **解決方法 5**: システム設定変更
5. **解決方法 4**: ローカルnixpkgs（最終手段）

---

## ⚠️ 注意事項

- すべてのコマンドはsudo権限が必要
- 解決方法2は従来方式のためflakeの一部機能が制限される
- 解決方法4は約2GBのダウンロードが必要

---

## 🎯 成功確認

実行成功後、以下で確認：

```bash
# システム世代確認
darwin-rebuild --list-generations

# アプリケーション確認
ls /Applications | grep -E "(DaVinci|Steam|Code)" | wc -l

# nix管理パッケージ確認
nix-env --query --installed | wc -l
```

48個のGUIアプリケーションがインストールされ、プロフェッショナル環境が完成します。