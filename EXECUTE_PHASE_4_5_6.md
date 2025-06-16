# 🚀 Phase 4, 5, 6 実行手順

**実行日**: 2025年6月16日 12:45 JST  
**ステータス**: 設定準備完了 - 手動実行が必要  
**移行アプリ数**: 40個（Phase 4: 11個 + Phase 5: 28個 + Phase 6: 1個）

---

## 📋 実行すべきコマンド

### 1. nix-darwin システム更新
```bash
cd ~/dotfiles
USER=yuki sudo darwin-rebuild switch --flake ~/.config/nix-darwin
```

### 2. 完了後の検証
```bash
# インストールされたアプリケーションの確認
ls /Applications | grep -E "(Docker|GIMP|Firefox|VLC|VS Code)"

# nix環境の確認
nix-env --query --installed

# システム状態の確認
darwin-rebuild --list-generations
```

---

## 📦 適用される変更内容

### Phase 4（既に準備済み）
```
docker          # Container runtime
firefox         # Web browser  
vlc             # Media player
obs-studio      # Screen recording
gimp            # Image editor
inkscape        # Vector graphics
krita           # Digital painting
thunderbird     # Email client
blender         # 3D modeling
libreoffice     # Office suite
qbittorrent     # Torrent client
```

### Phase 5（既に準備済み）
```
# Development Tools
vscode          # Visual Studio Code
zed-editor      # Modern text editor
virtualbox      # Virtualization
podman-desktop  # Container management
godot_4         # Game engine
freecad         # CAD software
kicad           # PCB design
goxel           # Voxel editor

# Creative Applications  
scribus         # Desktop publishing
fontforge       # Font editor
natron          # Compositing
opentoonz       # 2D animation

# Browsers
vivaldi         # Feature-rich browser
tor-browser     # Privacy browser

# Media Applications
musescore       # Music notation
mixxx           # DJ software  
surge-XT        # Synthesizer

# Gaming
prismlauncher   # Minecraft launcher

# Productivity & Utilities
obsidian        # Knowledge management
zotero          # Reference manager
bitwarden-desktop # Password manager
espanso         # Text expander
syncthing       # File synchronization
spacedrive      # File manager
rustdesk        # Remote desktop
wireshark       # Network analyzer
onlyoffice-bin  # Office suite
ollama          # Local LLM runner
```

### Phase 6（新発見）
```
figma           # Design tool
```

---

## ⚠️ 実行前の注意事項

### 1. バックアップ確認
- システム状態: `darwin-rebuild --list-generations`
- 設定ファイル: `nix/darwin.nix.phase4.backup`存在確認

### 2. 予想される動作
- **新規インストール**: 約40個のアプリケーション
- **実行時間**: 15-30分（ダウンロード・ビルド時間）
- **ディスク使用量**: 追加で5-10GB程度

### 3. トラブルシューティング
```bash
# ビルドエラーの場合
nix-collect-garbage -d
sudo darwin-rebuild switch --flake ~/.config/nix-darwin --show-trace

# 権限エラーの場合  
sudo chown -R $(whoami) /nix
```

---

## ✅ 実行後の確認項目

### 1. アプリケーション起動確認
```bash
# 重要なアプリの起動テスト
open -a "Visual Studio Code"
open -a "Firefox"  
open -a "VLC"
open -a "Figma"
```

### 2. システム安定性確認
```bash
# システムの状態確認
system_profiler SPApplicationsDataType | grep -A3 "Visual Studio Code"
```

### 3. Homebrew cask削除（オプション）
```bash
# 重複するHomebrew caskの削除
brew uninstall --cask visual-studio-code figma
# 注意: 必要に応じて実行
```

---

## 🎯 期待される結果

### システム管理比率
- **nix管理**: 131個のパッケージ（CLI: 90個 + GUI: 41個）
- **Homebrew管理**: 35個のアプリ（戦略的保持）
- **管理比率**: 79% nix / 21% Homebrew

### パフォーマンス向上
- **決定論的ビルド**: 完全な環境再現性
- **原子的更新**: 失敗しないシステム更新
- **ロールバック機能**: 任意の過去状態への復帰

---

## 🚨 緊急時の対応

### システムが起動しない場合
```bash
# 前の世代に戻す
sudo darwin-rebuild rollback

# または特定の世代を指定
sudo darwin-rebuild switch --rollback
```

### 一部アプリが動作しない場合
```bash
# 個別アプリの再インストール
nix-env -iA nixpkgs.vscode
```

---

**実行準備完了！上記のコマンドを実行してください。**

**🤖 Generated with [Claude Code](https://claude.ai/code)**  
**Co-Authored-By: Claude <noreply@anthropic.com>**