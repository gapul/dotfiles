# 🚀 Darwin Rebuild - 正しい実行手順

**問題**: restricted modeエラーでflakeが読み込めない  
**解決**: dotfiles/nixディレクトリから直接実行する

---

## 📋 正しい実行コマンド

### 方法1: dotfiles/nixディレクトリから実行
```bash
cd ~/dotfiles/nix
USER=yuki sudo darwin-rebuild switch --flake .
```

### 方法2: 絶対パスで指定
```bash
cd ~/dotfiles
USER=yuki sudo darwin-rebuild switch --flake ./nix
```

### 方法3: ホスト名を明示的に指定
```bash
cd ~/dotfiles/nix
USER=yuki sudo darwin-rebuild switch --flake .#Yukis-Laptop
```

---

## 🔍 現在の設定状況

### ✅ 準備完了項目
- **flake.nix**: dotfiles/nix/に存在
- **darwin.nix**: Phase 4, 5, 6のアプリ（40個）を含む
- **flake.lock**: 最新版に更新済み
- **nix.conf**: parallel-shell-jobs設定をコメントアウト済み

### 📦 インストール予定アプリ (40個)
```
Phase 4 (11個): docker, firefox, vlc, obs-studio, gimp, 
                inkscape, krita, thunderbird, blender, 
                libreoffice, qbittorrent

Phase 5 (28個): vscode, zed-editor, virtualbox, podman-desktop,
                godot_4, freecad, kicad, goxel, scribus,
                fontforge, natron, opentoonz, vivaldi, 
                tor-browser, musescore, mixxx, surge-XT,
                prismlauncher, obsidian, zotero, 
                bitwarden-desktop, espanso, syncthing,
                spacedrive, rustdesk, wireshark,
                onlyoffice-bin, ollama

Phase 6 (1個): figma
```

---

## ⏱️ 実行時の予想

### タイムライン
- **ダウンロード**: 5-10分（アプリケーションサイズによる）
- **ビルド・インストール**: 10-20分
- **設定適用**: 2-3分
- **合計**: 約20-30分

### ディスク使用量
- **追加容量**: 約8-12GB
- **nix store**: 約6-8GB増加
- **/Applications**: GUI アプリのエイリアス作成

---

## 🚨 実行前チェックリスト

### システム要件確認
```bash
# 空き容量確認 (15GB以上推奨)
df -h /

# メモリ使用量確認
vm_stat

# 実行中のプロセス確認
pgrep -f nix
```

### バックアップ確認
```bash
# 現在の世代を記録
darwin-rebuild --list-generations

# バックアップファイル確認
ls -la nix/*backup*
```

---

## 🔧 エラー時のトラブルシューティング

### もしrestricted modeエラーが続く場合
```bash
# flakeの構文チェック
cd ~/dotfiles/nix
nix flake check

# Nixデーモン再起動
sudo launchctl stop org.nixos.nix-daemon
sudo launchctl start org.nixos.nix-daemon
```

### ビルドエラーの場合
```bash
# ガベージコレクション
nix-collect-garbage -d
sudo nix-collect-garbage -d

# 詳細ログ付きで再実行
cd ~/dotfiles/nix
USER=yuki sudo darwin-rebuild switch --flake . --show-trace -v
```

### 権限エラーの場合
```bash
# nix権限修正
sudo chown -R $(whoami) /nix/var/nix/profiles/per-user/$(whoami)
```

---

## ✅ 成功の確認方法

### アプリケーション確認
```bash
# GUIアプリの確認
ls /Applications | grep -E "(Code|Firefox|VLC|Figma)"

# CLI ツールの確認
which docker firefox figma
```

### nix環境確認
```bash
# インストール済みパッケージ確認
nix-env --query --installed | wc -l

# システム世代確認
darwin-rebuild --list-generations
```

---

**実行準備完了！上記のいずれかの方法でdarwin-rebuildを実行してください。**

**推奨**: 方法1（cd ~/dotfiles/nix && USER=yuki sudo darwin-rebuild switch --flake .）