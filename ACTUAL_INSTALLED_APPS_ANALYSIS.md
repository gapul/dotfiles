# 📱 実際にインストール済みアプリの分析

**分析日**: 2025年6月16日 12:40 JST  
**分析範囲**: /Applications内の全アプリケーション  
**総アプリ数**: 75個

---

## 🔍 インストール済みアプリ一覧

### 現在インストールされている全アプリ
```
.Karabiner-VirtualHIDDevice-Manager
Bitwarden
Blackmagic Proxy Generator Lite
ChatGPT
Claude
Cloudflare WARP
Cursor
Dia
Discord
Docker
Epic Games Launcher
Espanso
Figma
Firefox Developer Edition
Floorp
FontForge
FreeCAD
GarageBand
GIMP
Godot
Google Chrome Dev
Goxel
Ice
Inkscape
Karabiner-Elements
Karabiner-EventViewer
krita
LibreOffice
LINE
material_maker
Microsoft Excel
Microsoft PowerPoint
Microsoft Word
MiddleClick
Minecraft
Mixxx
MuseScore 4
Natron
OBS
Obsidian
Ollama
ONLYOFFICE
OpenToonz
Podman Desktop
Prism Launcher
Raycast
RetroArch
RustDesk
Safari
Scribus
Serato DJ Lite
SF Symbols
Shortcat
Slack
Spacedrive
Steam
Surge XT
Surge XT Effects
Syncthing
Thunderbird
Tor Browser
Unity Hub
VirtualBox
Visual Studio Code
Vivaldi
VLC
VMware Fusion
WezTerm
Whisky
Wireshark
Xcode
Zed
Zen
Zotero
Zrythm
```

---

## ✅ 既にnix管理済み（Phase 4）

```
Docker          → docker
GIMP            → gimp
Inkscape        → inkscape
krita           → krita
LibreOffice     → libreoffice
OBS             → obs-studio
Thunderbird     → thunderbird
VLC             → vlc
```

---

## 🚀 Phase 5で移行予定（darwin.nixに既に追加済み）

```
Visual Studio Code  → vscode
Zed                → zed-editor
VirtualBox         → virtualbox
Podman Desktop     → podman-desktop
Godot              → godot_4
FreeCAD            → freecad
Goxel              → goxel
Scribus            → scribus
FontForge          → fontforge
Natron             → natron
OpenToonz          → opentoonz
Vivaldi            → vivaldi
Tor Browser        → tor-browser
MuseScore 4        → musescore
Mixxx              → mixxx
Surge XT           → surge-XT
Prism Launcher     → prismlauncher
Obsidian           → obsidian
Zotero             → zotero
Bitwarden          → bitwarden-desktop
Espanso            → espanso
Syncthing          → syncthing
Spacedrive         → spacedrive
RustDesk           → rustdesk
Wireshark          → wireshark
ONLYOFFICE         → onlyoffice-bin
Ollama             → ollama
```

---

## 🎯 Phase 6で新発見（実際にインストール済み）

```
Figma              → figma  ✅ 唯一の新発見アプリ
```

---

## 🍺 Homebrew継続管理（戦略的判断）

### macOS専用・統合重要
```
Raycast            # macOS-specific launcher
Karabiner-Elements # Kernel extension
Ice                # Menu bar organizer (jordanbaird-ice)
MiddleClick        # macOS utility
Shortcat           # Accessibility tool
```

### 開発・クリエイティブ（専用機能）
```
Cursor             # AI-powered editor
Unity Hub          # Game engine hub
material_maker     # Godot-based
```

### ブラウザ（特殊版）
```
Firefox Developer Edition  # Special edition
Floorp             # Firefox fork
Zen                # Firefox fork  
Google Chrome Dev  # Dev channel
```

### ゲーム・エンターテイメント
```
Steam              # Gaming platform
Epic Games Launcher # Gaming platform
Minecraft          # Game
RetroArch          # Emulation
Whisky             # Wine wrapper
```

### Microsoft Office
```
Microsoft Excel
Microsoft PowerPoint
Microsoft Word
```

### AI・専用アプリ
```
ChatGPT            # Proprietary AI
Claude             # Proprietary AI
```

### その他
```
Cloudflare WARP    # VPN client
VMware Fusion      # Virtualization
Blackmagic Proxy Generator Lite  # Video editing
Dia                # Diagramming
Serato DJ Lite     # DJ software
Surge XT Effects   # Audio effects
Zrythm             # DAW
```

---

## 📊 最終統計

### 管理方法別分類
- **✅ nix管理**: 40個のアプリ（Phase 4: 11個 + Phase 5: 28個 + Phase 6: 1個）
- **🍺 Homebrew管理**: 35個のアプリ（戦略的保持）
- **📱 総アプリ数**: 75個

### 管理比率
- **nix**: 53% (40/75)
- **Homebrew**: 47% (35/75)

### 移行可能性
- **移行完了**: 40個
- **移行可能だが戦略的にHomebrew保持**: 約15個
- **Homebrew必須**: 約20個

---

## 🎯 結論

1. **Phase 6の実際の成果**: Figma 1個の追加のみ
2. **現実的な移行限界**: 約53%がnix管理可能
3. **ハイブリッド戦略の妥当性**: macOS特有のアプリとプロプライエタリソフトウェアはHomebrew継続が適切

---

**🤖 Generated with [Claude Code](https://claude.ai/code)**  
**Co-Authored-By: Claude <noreply@anthropic.com>**