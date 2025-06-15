# 現在のHomebrew環境分析

> **nix移行のための現状把握**

## 📊 インストール済みパッケージ概要

### 数量サマリー
- **Formula**: ~150個のCLIツール・ライブラリ
- **Cask**: ~80個のGUIアプリケーション  
- **Services**: 5個（sketchybar起動中）
- **Taps**: 5個のサードパーティリポジトリ

## 🔧 主要カテゴリ分析

### 1️⃣ 開発ツール（Critical）
**CLIツール:**
- `git`, `gh` - Git管理
- `neovim` - エディター
- `ripgrep`, `tree`, `jq` - 検索・解析
- `shellcheck` - スクリプト検証
- `make`, `cmake` - ビルドツール
- `node`, `nodebrew` - Node.js環境
- `python@3.12`, `python@3.13` - Python環境

**GUIアプリ:**
- `visual-studio-code`, `zed`, `cursor` - エディター
- `docker` - コンテナ環境
- `android-studio` - モバイル開発
- `figma-agent` - デザインツール

### 2️⃣ システムツール（Critical）
**ウィンドウ管理:**
- `yabai` - タイル型ウィンドウマネージャー
- `skhd` - キーバインド管理
- `sketchybar` - ステータスバー（起動中サービス）

**ターミナル・シェル:**
- `wezterm` - ターミナルエミュレータ
- `starship` - プロンプト

### 3️⃣ メディア・クリエイティブ（Medium）
**動画・音声:**
- `ffmpeg` - 動画処理（多数の依存関係）
- `audacity`, `mixxx` - 音声編集
- `obs` - 配信・録画

**グラフィック・3D:**
- `blender`, `freecad` - 3Dモデリング
- `gimp`, `inkscape`, `krita` - 画像編集
- `darktable` - RAW現像

### 4️⃣ 日常アプリ（Low）
**ブラウザ:**
- `arc`, `firefox@developer-edition`, `google-chrome@dev`
- `floorp`, `vivaldi`, `zen-browser`

**コミュニケーション:**
- `discord`, `slack`, `beeper`
- `thunderbird` - メール

**ユーティリティ:**
- `raycast` - ランチャー
- `karabiner-elements` - キーボード設定

### 5️⃣ 特殊なTaps
- `felixkratz/formulae` - sketchybar
- `koekeishiya/formulae` - yabai, skhd
- `voicevox/voicevox` - 音声合成
- `grishka/grishka` - 特殊ツール

## 🎯 nix移行時の考慮事項

### ✅ nix対応確実
- 基本的な開発ツール（git, neovim, python, node）
- 標準的なCLIユーティリティ
- 一般的なGUIアプリケーション

### ⚠️ 要検証
- カスタムTaps（yabai, sketchybar, skhd）
- 日本語特化ツール（voicevox等）
- 最新版要求アプリ（developer edition系）

### ❌ nix困難
- App Store専用アプリ
- ライセンス制約アプリ（Microsoft Office等）
- macOS固有の深いシステム統合アプリ

## 📋 依存関係の複雑性

### 高依存パッケージ
- `ffmpeg`: 30+の依存関係（メディア処理）
- `imagemagick`: グラフィック処理ライブラリ群
- `python@3.x`: 科学計算・開発ライブラリ
- `mysql`: データベース関連

### システムサービス
- `sketchybar`: 現在起動中（重要）
- `mysql`, `openvpn`: 停止中だが設定済み

この分析を基に、段階的なnix移行戦略を立案します。