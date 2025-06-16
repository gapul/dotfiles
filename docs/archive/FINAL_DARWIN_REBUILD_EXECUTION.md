# 🚀 Final Darwin Rebuild 実行手順

**最終段階**: Phase 4-7の48個のGUIアプリケーションをnix管理下に移行

---

## 📋 実行コマンド

### 方法1: --impureフラグ使用（推奨）
```bash
cd ~/dotfiles/nix
USER=yuki sudo darwin-rebuild switch --flake . --impure
```

### 方法2: flake.lock更新 + 通常実行
```bash
cd ~/dotfiles/nix
nix flake update
USER=yuki sudo darwin-rebuild switch --flake .
```

### 方法3: flakeなしで実行
```bash
cd ~/dotfiles/nix
USER=yuki sudo darwin-rebuild switch --impure -I darwin-config=./darwin.nix
```

---

## 🎯 実行されるPhase 4-7の全内容

### Phase 4: GUI Applications (11個)
```
docker          # Container runtime
firefox         # Web browser
vlc             # Media player
obs-studio      # Screen recording/streaming
gimp            # Image editor
inkscape        # Vector graphics editor
krita           # Digital painting
thunderbird     # Email client
blender         # 3D modeling
libreoffice     # Office suite
qbittorrent     # Torrent client
```

### Phase 5: Maximum Migration (28個)
```
# Development Tools
vscode          # Visual Studio Code
zed-editor      # Modern text editor
virtualbox      # Virtualization platform
podman-desktop  # Container management
godot_4         # Game engine
freecad         # CAD software
kicad           # PCB design
goxel           # Voxel editor

# Creative Applications
scribus         # Desktop publishing
fontforge       # Font editor
natron          # Compositing software
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

### Phase 6: Discovery (1個)
```
figma           # Design tool (discovered and verified)
```

### Phase 7: Professional Apps (8個)
```
davinci-resolve    # Professional video editing software
firefox-devedition # Firefox Developer Edition
floorp             # Privacy-focused browser
minecraft          # Minecraft Java Edition
retroarch          # Retro gaming emulator
steam              # Gaming platform
wezterm            # Modern terminal emulator
zrythm             # Professional DAW
```

---

## ⏱️ 実行時の予想

### ダウンロード・ビルド時間
- **DaVinci Resolve**: 約10-15分（大容量）
- **Steam**: 約5-10分
- **その他46個**: 約15-25分
- **合計予想時間**: 30-50分

### ディスク使用量
- **追加容量**: 約15-25GB
- **DaVinci Resolve**: 約8-10GB
- **Steam + ゲーム関連**: 約3-5GB
- **その他アプリ**: 約4-10GB

---

## 🔧 トラブルシューティング

### もしrestricted modeエラーが続く場合
```bash
# Nixデーモン再起動
sudo launchctl stop org.nixos.nix-daemon
sudo launchctl start org.nixos.nix-daemon

# 方法1を再試行
cd ~/dotfiles/nix
USER=yuki sudo darwin-rebuild switch --flake . --impure
```

### ビルドエラーの場合
```bash
# ガベージコレクション
nix-collect-garbage -d
sudo nix-collect-garbage -d

# 詳細ログで再実行
cd ~/dotfiles/nix
USER=yuki sudo darwin-rebuild switch --flake . --impure --show-trace -v
```

### 個別パッケージがビルド失敗した場合
```bash
# 問題のパッケージを確認
nix-env -f '<nixpkgs>' -qaP | grep -E "(davinci|steam|zrythm)"

# 個別テスト
nix shell nixpkgs#davinci-resolve
```

---

## ✅ 成功の確認方法

### 重要アプリの起動テスト
```bash
# プロフェッショナルアプリ
open -a "DaVinci Resolve"
open -a "Zrythm"

# ゲーミング
open -a "Steam"
open -a "Minecraft"

# 開発ツール
open -a "Visual Studio Code"
open -a "WezTerm"

# ブラウザ
open -a "Firefox Developer Edition"
open -a "Floorp"
```

### システム状態確認
```bash
# nix管理アプリ数確認
nix-env --query --installed | wc -l

# システム世代確認
darwin-rebuild --list-generations

# アプリケーション確認
ls /Applications | grep -E "(DaVinci|Steam|Code|Zrythm)" | wc -l
```

---

## 🎉 完了後の環境

### システム管理比率
- **nix管理**: 139個のパッケージ（CLI: 91個 + GUI: 48個）
- **Homebrew管理**: 約24個のアプリ（戦略的保持）
- **管理比率**: 85% nix / 15% Homebrew

### 新機能獲得
- **ハリウッド品質の動画編集**（DaVinci Resolve）
- **プロ音楽制作環境**（Zrythm）
- **完全なゲーミング体験**（Steam + Minecraft + RetroArch）
- **最先端開発環境**（WezTerm + Firefox DevEdition）

---

## 🚨 緊急時の対応

### システムが起動しない場合
```bash
# 前の世代に戻す
sudo darwin-rebuild rollback

# 特定の世代を指定
sudo darwin-rebuild switch --rollback
```

### 一部アプリが動作しない場合
```bash
# アプリケーション再インストール
nix-env -e davinci-resolve
nix-env -iA nixpkgs.davinci-resolve
```

---

**実行準備完了！上記のいずれかの方法でdarwin-rebuildを実行してください。**

**推奨**: 方法1（--impureフラグ）を最初に試してください。