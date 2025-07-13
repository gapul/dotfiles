# QMK/VIA Custom Keyboard Integration Guide

このガイドでは、dotfilesシステムに統合されたQMK/VIAカスタムキーボード機能の使用方法を説明します。

## 🎯 概要

QMK/VIA統合システムは以下の機能を提供します：

- **QMK Firmware**: カスタムキーボードファームウェアの開発・管理
- **VIA Configuration**: リアルタイムキーマップ編集
- **AI最適化**: 使用パターンに基づくキーマップ最適化
- **プロファイル管理**: 用途別キーマップテンプレート
- **自動化ツール**: ファームウェアコンパイル・フラッシュ支援

## 🚀 クイックスタート

### 1. 初期セットアップ

```bash
# QMK開発環境のセットアップ
qmk-setup

# VIAアプリケーションの起動（既にインストール済み）
via-open

# システムヘルスチェック
qmk-health
```

### 2. サポートキーボード

現在サポートされているキーボード：

- **Planck**: 4x12オルソリニアキーボード
- **Corne (CRKBD)**: 分割型3x6キーボード
- **Lily58**: 分割型4x6キーボード
- **ErgoDox EZ**: エルゴノミクスキーボード
- **Moonlander**: ZSAの高機能キーボード
- **Preonic**: Planckの大型版
- **Kyria**: 分割型エルゴノミクスキーボード

### 3. プリセットプロファイル

#### 開発者プロファイル (`developer`)
```bash
# 開発者向けキーマップの作成
qmk-keymap create planck dev-layout

# AI最適化の実行
qmk-ai planck developer
```

**特徴:**
- プログラミング記号への高速アクセス
- Git/開発ツール用マクロ
- コード編集最適化レイヤー
- ホームロウモディファイア

#### ライタープロファイル (`writer`)
```bash
# ライター向けキーマップの作成
qmk-keymap create lily58 writer-layout
```

**特徴:**
- テキスト編集ショートカット
- 文書ナビゲーション最適化
- 句読点・特殊文字の効率配置
- スマートクォート・記号入力

#### ゲーマープロファイル (`gamer`)
```bash
# ゲーマー向けキーマップの作成
qmk-keymap create corne gaming-layout
```

**特徴:**
- WASD最適化レイアウト
- ゲーミングマクロ対応
- RGB効果との連携
- 低レイテンシー設定

## 🛠️ 詳細操作

### キーマップ管理

```bash
# 利用可能なキーボード・キーマップ一覧
qmk-keymap list

# 新しいキーマップの作成
qmk-keymap create <keyboard> <keymap_name>

# キーマップのコンパイル
qmk-keymap compile <keyboard> <keymap_name>

# キーマップのフラッシュ（キーボードをブートローダーモードに）
qmk-keymap flash <keyboard> <keymap_name>

# キーマップのバックアップ
qmk-keymap backup
```

### AI最適化機能

```bash
# AI最適化レコメンデーションの生成
qmk-ai-optimizer <keyboard> [profile]

# 使用例
qmk-ai-optimizer planck developer
qmk-ai-optimizer lily58 writer
qmk-ai-optimizer corne gamer
```

**AI最適化の内容:**
- レイヤー構成の最適化提案
- キー配置の効率化
- 用途別マクロ提案
- タップダンス・コンボ最適化
- RGB照明パターン提案

### VIA統合

```bash
# VIAアプリケーションを開く
via-open

# VIA設定の確認
cat ~/.config/via/settings.json
```

**VIA機能:**
- リアルタイムキーマップ編集
- マクロの録画・編集
- RGB照明制御
- ロータリーエンコーダー設定
- レイヤー可視化

## 🎨 カスタマイズ

### レイヤー構成

標準的な4レイヤー構成：

1. **Base Layer**: メインタイピングレイヤー
2. **Symbols/Numbers**: 記号・数字レイヤー
3. **Navigation**: ナビゲーション・ファンクションキー
4. **System/RGB**: システム制御・RGB設定

### マクロ例

#### 開発者向けマクロ
```json
{
  "name": "Git Status",
  "keys": ["KC_G", "KC_I", "KC_T", "KC_SPC", "KC_S", "KC_T", "KC_A", "KC_T", "KC_U", "KC_S", "KC_ENT"]
}
```

#### ライター向けマクロ
```json
{
  "name": "Em Dash",
  "keys": ["KC_MINS", "KC_MINS"],
  "result": "UC(0x2014)"
}
```

### RGB照明設定

```json
{
  "defaultMode": "RGB_MODE_RAINBOW_SWIRL",
  "brightness": 128,
  "layerIndication": true,
  "capsLockIndication": true
}
```

## 🔧 開発者向け機能

### カスタムファームウェア開発

```bash
# 開発環境の有効化（設定で有効化が必要）
# development.enable = true;

# QMKファームウェアディレクトリへの移動
qmk-dev

# カスタムキーボードの追加
cd keyboards/
mkdir my_custom_keyboard
```

### デバッグ機能

```bash
# QMKデバッガーの使用（要設定）
# development.debugger = true;

# キーボードシミュレーター（要設定）
# development.simulator = true;
```

## 📊 ヘルスモニタリング

```bash
# 完全なヘルスチェック
qmk-health-monitor
```

**チェック項目:**
- QMK CLI インストール状況
- VIA アプリケーション状況
- 接続キーボードの検出
- カスタムキーマップの状況
- AI統合機能の状況
- システムキーボード設定

## 🎯 トラブルシューティング

### よくある問題

#### QMK CLIがインストールされない
```bash
# 手動インストール
pip3 install --user qmk
# または
brew install qmk/qmk/qmk
```

#### VIAでキーボードが認識されない
```bash
# キーボードをブートローダーモードに
# または
# VIA対応ファームウェアの確認
```

#### ファームウェアのフラッシュに失敗
```bash
# ブートローダーモードの確認
# USBケーブルの確認
# 権限問題の確認
```

### AI機能トラブルシューティング

```bash
# Ollamaサービスの確認
ollama-manager status

# Ollamaサービスの開始
ollama-manager start

# AIモデルの確認
ollama-manager models list
```

## 🔒 セキュリティ

- **ファームウェア検証**: 信頼できるソースからのみファームウェアを使用
- **手動フラッシュ**: 自動フラッシュは無効化（安全性のため）
- **バックアップ**: キーマップの定期バックアップ
- **段階的変更**: 大きな変更は段階的に実行

## 📚 参考資料

- [QMK公式ドキュメント](https://docs.qmk.fm/)
- [VIA公式サイト](https://www.caniusevia.com/)
- [QMK Configurator](https://config.qmk.fm/)
- [キーマップデータベース](https://keymaps.qmk.fm/)

## 🤝 コミュニティ

- [QMK Discord](https://discord.gg/qmk)
- [r/MechanicalKeyboards](https://reddit.com/r/MechanicalKeyboards)
- [r/ErgoMechKeyboards](https://reddit.com/r/ErgoMechKeyboards)

---

*最終更新: 2025年7月12日*
*QMK/VIA統合システム v1.0*