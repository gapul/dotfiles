# 📦 nixpkgsで利用可能なアプリケーション分析結果

**分析日**: 2025年6月16日 JST  
**対象**: インストール済みアプリのnixpkgs対応状況  
**検索範囲**: Bitwarden, Blackmagic, Dia, Firefox Dev, Floorp, GarageBand, LINE, Minecraft, RetroArch, Serato, Steam, Surge XT, WezTerm, Xcode, Zen, Zrythm, DaVinci Resolve

---

## ✅ nixpkgsで利用可能なアプリケーション

### 🎯 即座に追加可能（高優先度）
```nix
davinci-resolve        # プロ動画編集ソフト（20.0）
firefox-devedition     # Firefox Developer Edition
floorp                 # プライバシー重視ブラウザ
minecraft              # Minecraft Java Edition
retroarch              # レトロゲームエミュレーター
steam                  # Steamゲームプラットフォーム
wezterm                # モダンターミナルエミュレーター
zrythm                 # プロオーディオ制作DAW
```

### 📋 現在の分類状況
```nix
# 既にnix管理済み（Phase 4-6で追加済み）
dia                    # ダイアグラム作成ツール（Phase 5で追加済み）

# バリアント選択が必要
minecraft-launcher     # 公式ランチャー版
minecraft-server       # サーバー版
prismlauncher         # 軽量ランチャー（Phase 5で追加済み）
```

---

## ❓ 部分的または関連パッケージのみ利用可能

### 🔧 Blackmagic関連
```bash
# 検索結果: blackmagic-desktop-video, ffmpeg-blackmagic-sdk など
# ただし「Blackmagic Proxy Generator Lite」は直接対応なし
❌ blackmagic-proxy-generator-lite  # 利用不可
✅ blackmagic-desktop-video         # 関連ツール
✅ blackmagic-sdk                   # 開発キット
```

### 💬 LINE関連
```bash
# 検索結果: line-drawing, line-profiler など多数
# ただし「LINE メッセンジャー」アプリは直接対応なし
❌ line-messenger      # メッセンジャーアプリは利用不可
✅ line-*             # 他のlineツール多数（開発関連）
```

### 🛠️ Xcode関連
```bash
# 検索結果: xcode-build-tools, xcodes など
❌ xcode              # Xcode IDE本体は利用不可
✅ xcodes             # Xcode管理ツール
✅ xcode-build-tools  # ビルドツール
```

---

## ❌ nixpkgsで利用不可（Homebrew必須）

### 🎵 プロプライエタリ音楽アプリ
```
❌ garageband         # Apple製DAW
❌ serato-dj-lite     # DJソフトウェア
```

### 🌐 新しいブラウザ
```
❌ zen-browser        # 比較的新しいブラウザ
```

### 🎮 オーディオプラグイン
```
❌ surge-xt-effects   # 直接的な対応なし
# ただし surge-XT本体は Phase 5で追加済み
```

---

## 🚀 推奨アクション

### Phase 7提案: 高価値アプリケーション追加
```nix
# nix/darwin.nix に追加可能
environment.systemPackages = with pkgs; [
  # Phase 7: High-Value Applications
  davinci-resolve        # プロ動画編集（最優先）
  firefox-devedition     # 開発者向けブラウザ
  floorp                 # プライバシーブラウザ
  minecraft              # ゲーム
  retroarch              # レトロゲーミング
  steam                  # ゲームプラットフォーム
  wezterm                # ターミナル（Phase 2で追加済みの可能性あり）
  zrythm                 # プロDAW
];
```

### Homebrew継続管理
```ruby
# プロプライエタリアプリはHomebrew継続
"garageband"           # Apple製DAW
"serato-dj-lite"       # DJ software
"zen-browser"          # 新しいブラウザ
"blackmagic-proxy-generator-lite"  # Blackmagic tool
```

---

## 📊 統計サマリー

### 対応状況
- **✅ 完全対応**: 8個（davinci-resolve, firefox-devedition, floorp, minecraft, retroarch, steam, wezterm, zrythm）
- **📋 既に管理済み**: 1個（dia）
- **❓ 部分対応**: 3個（blackmagic関連, line関連, xcode関連）
- **❌ 非対応**: 4個（garageband, serato, zen-browser, surge-xt-effects）

### 価値評価
- **高価値**: davinci-resolve（プロ動画編集）
- **開発者向け**: firefox-devedition, wezterm
- **エンターテイメント**: minecraft, retroarch, steam
- **音楽制作**: zrythm

---

## 💡 次のステップ

1. **即座実行可能**: Phase 7として上記8個のアプリを追加
2. **重複確認**: wezterm, diaが既に管理済みかチェック
3. **DaVinci Resolve優先**: プロ動画編集機能の大幅強化
4. **ゲーミング強化**: Steam + RetroArch + Minecraftの統合

---

**🤖 Generated with [Claude Code](https://claude.ai/code)**  
**Co-Authored-By: Claude <noreply@anthropic.com>**

*インストール済みアプリケーションのnixpkgs対応状況分析完了*