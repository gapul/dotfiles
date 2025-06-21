# AeroSpace Migration Guide

## 概要

yabai + skhd から AeroSpace への移行が完了しました。AeroSpaceは現代的なタイリングウィンドウマネージャーで、より安定性と使いやすさに重点を置いています。

## 変更内容

### 🔄 移行されたコンポーネント

#### 1. Homebrewパッケージ変更
**Before:**
```nix
taps = [
  "koekeishiya/formulae"  # yabai, skhd
  "felixkratz/formulae"   # sketchybar
];

brews = [
  "yabai"
  "skhd" 
  "sketchybar"
];
```

**After:**
```nix
taps = [
  "nikitabobko/tap"       # AeroSpace
  "felixkratz/formulae"   # sketchybar
];

brews = [
  "aerospace"
  "sketchybar"
];
```

#### 2. 設定ファイル
- **新規**: `configs/aerospace/aerospace.toml`
- **自動配置**: `~/.config/aerospace/aerospace.toml`

### ⌨️ デフォルトキーバインド (AeroSpace)

#### ウィンドウフォーカス
- `Alt + h/j/k/l`: ウィンドウフォーカス移動

#### ウィンドウ移動
- `Alt + Shift + h/j/k/l`: ウィンドウ移動

#### ワークスペース
- `Alt + 1-9, a-z`: ワークスペース切り替え
- `Alt + Shift + 1-9, a-z`: ウィンドウをワークスペースに移動
- `Alt + Tab`: 前のワークスペースに戻る

#### レイアウト制御
- `Alt + /`: タイルレイアウト
- `Alt + ,`: アコーディオンレイアウト

#### リサイズ
- `Alt + Shift + -`: 賢いリサイズ（縮小）
- `Alt + Shift + =`: 賢いリサイズ（拡大）

#### サービスモード
- `Alt + Shift + ;`: サービスモード入入

#### サービスモード内
- `Esc`: 設定リロード＆メインモード復帰
- `r`: レイアウトリセット＆メインモード復帰
- `f`: フローティング/タイリング切り替え
- `Backspace`: 現在のウィンドウ以外を閉じる
- `Alt + Shift + h/j/k/l`: ウィンドウを結合

#### マルチモニター
- `Alt + Shift + Tab`: ワークスペースを次のモニターに移動

### 🎛️ ギャップとパディング設定
- **内側ギャップ**: 10px (水平・垂直)
- **外側ギャップ**: 10px (全方向)
- **アコーディオンパディング**: 30px

## 📝 移行手順

### 1. システム適用
```bash
cd ~/dotfiles/nix
sudo darwin-rebuild switch --flake .#default --impure
```

**✅ 自動実行される内容**:
- yabai, skhdの自動削除
- AeroSpaceの自動インストール
- tapの自動変更（koekeishiya/formulae → nikitabobko/tap）
- 設定ファイルの自動配置

### 2. AeroSpace起動
```bash
# AeroSpaceアプリケーション起動
open /Applications/AeroSpace.app

# または、システム起動時自動起動が有効化済み
```

### 3. 設定確認
```bash
# AeroSpace設定確認
aerospace list-workspaces

# 設定リロード
aerospace reload-config
```

## 🔧 カスタマイズ

### 設定ファイル場所
- **システム**: `configs/aerospace/aerospace.toml`
- **ユーザー**: `~/.config/aerospace/aerospace.toml`

### よくあるカスタマイズ
1. **キーバインド変更**: `[mode.main.binding]` セクションを編集
2. **ワークスペース追加**: `alt-0` など追加キーを定義
3. **アプリ自動配置**: `[[on-window-detected]]` セクションに追加

## 🚀 AeroSpaceの利点

### vs yabai + skhd
- ✅ **統一設定**: 1つのTOMLファイルで完結
- ✅ **安定性**: SIP無効化不要
- ✅ **現代的**: TOMLベース設定、直感的キーバインド
- ✅ **パフォーマンス**: 軽量、高速レスポンス
- ✅ **保守性**: シンプルな設定構造

### 新機能
- 🎯 **アコーディオンレイアウト**: 効率的な画面分割
- 🔄 **自動ノーマライゼーション**: ギャップ最適化
- 📱 **多モニター対応**: 強力な画面管理
- ⚡ **ホットリロード**: 設定変更の即座反映

## 🛠️ トラブルシューティング

### よくある問題

#### 1. AeroSpaceが起動しない
```bash
# Homebrewサービス確認
brew services list | grep aerospace

# 手動起動
aerospace
```

#### 2. キーバインドが効かない
```bash
# 設定ファイル確認
aerospace list-keys

# アクセシビリティ権限確認
# システム環境設定 > セキュリティとプライバシー > アクセシビリティ
```

#### 3. ワークスペース移動が不安定
```bash
# デバッグモード
aerospace --help

# 設定リロード
aerospace reload-config
```

## 📚 参考リンク

- [AeroSpace公式GitHub](https://github.com/nikitabobko/AeroSpace)
- [AeroSpace設定ドキュメント](https://github.com/nikitabobko/AeroSpace/blob/main/docs/config-reference.md)
- [Homebrewフォーミュラ](https://github.com/nikitabobko/homebrew-tap)

---

**移行完了日**: 2025年6月21日  
**ブランチ**: `aerospace-migration`  
**担当**: Claude Code CLI