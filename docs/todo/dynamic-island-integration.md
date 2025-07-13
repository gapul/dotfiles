# Dynamic Island Integration - TODO

**優先度**: 中  
**推定時間**: 4-6時間  
**ステータス**: 保留中（互換性問題により一時中断）

## 概要

iPhone 14 Pro風のDynamic Island機能を既存のSketchyBarに統合する。現在は互換性問題により無効化されているが、将来的な実装のため詳細を記録。

## 実装目標

- **Dynamic Island表示**: 画面上部中央にiPhone 14 Pro風の丸角矩形を表示
- **動的拡張**: コンテンツに応じてサイズが変化する
- **インタラクション**: クリック・ホバーでの操作対応
- **音楽統合**: 現在の再生情報を表示
- **システム統合**: 音量・明度・通知などの情報表示

## 現在の問題

### 1. Lua互換性問題
```lua
-- 問題のあるコード (Lua 5.2で動作しない)
return (color & 0x00ffffff) | (math.floor(alpha * 255.0) << 24)

-- 修正版 (bit32ライブラリ使用)
return bit32.bor(bit32.band(color, 0x00ffffff), bit32.lshift(math.floor(alpha * 255.0), 24))
```

### 2. アーキテクチャの不整合
- Dynamic Islandは独立したSketchyBarインスタンスとして設計
- 既存のSketchyBarとの併用が困難
- 単一SketchyBarインスタンス制限

### 3. 設定競合
- 既存のワークスペース管理設定との競合
- バー位置・サイズ設定の衝突

## 解決策候補

### アプローチ1: ネイティブ統合
```lua
-- 既存のSketchyBar設定に直接組み込み
local dynamic_island = sbar.add("item", "dynamic_island", {
    position = "center",
    -- 設定詳細
})
```

**メリット**: 統合性が高い  
**デメリット**: 複雑な設定調整が必要

### アプローチ2: プラグイン方式
```bash
# 独立したプラグインとして実装
./scripts/dynamic-island-plugin.sh &
```

**メリット**: 既存設定への影響最小  
**デメリット**: 統合感が低い

### アプローチ3: オーバーレイ方式
```bash
# 透明なオーバーレイウィンドウとして実装
swift run DynamicIslandOverlay &
```

**メリット**: 完全な独立性  
**デメリット**: システムリソース消費

## 実装ファイル

### 作成済みファイル
- `/configs/statusbar/sketchybar/items/dynamic_island.lua` - メイン実装
- `/scripts/start-dynamic-island.sh` - 起動スクリプト
- `~/.config/dynamic-island-sketchybar/userconfig.sh` - 設定ファイル

### 必要な追加ファイル
- `/scripts/dynamic-island-functions.lua` - ヘルパー関数
- `/configs/statusbar/sketchybar/themes/dynamic-island.lua` - テーマ設定

## 技術仕様

### 必要な依存関係
- ✅ SketchyBar 2.22.1+
- ✅ sf-symbols
- ✅ jq
- ⚠️ Lua 5.3+ (bit演算サポート)

### 設定パラメータ
```bash
# Dynamic Island寸法
P_DYNAMIC_ISLAND_DEFAULT_HEIGHT=36
P_DYNAMIC_ISLAND_DEFAULT_WIDTH=80
P_DYNAMIC_ISLAND_CORNER_RADIUS=18

# 機能有効化
P_DYNAMIC_ISLAND_MUSIC_ENABLED=1
P_DYNAMIC_ISLAND_VOLUME_ENABLED=1
P_DYNAMIC_ISLAND_BRIGHTNESS_ENABLED=1
```

## 実装手順

1. **Lua環境の確認**
   - Lua 5.3以降の利用可能性確認
   - bit32ライブラリの代替手段検討

2. **設定統合の設計**
   - 既存のSketchyBar設定との共存方法
   - 位置・サイズ競合の解決

3. **段階的実装**
   - 基本的な表示機能
   - 動的サイズ変更
   - インタラクション機能
   - システム情報統合

4. **テスト・調整**
   - 各種画面サイズでの動作確認
   - パフォーマンス最適化
   - 既存機能への影響確認

## 参考資料

- [元プロジェクト](https://github.com/crissNb/Dynamic-Island-Sketchybar)
- [SketchyBar公式ドキュメント](https://felixkratz.github.io/SketchyBar/)
- [実装済みファイル](/configs/statusbar/sketchybar/items/dynamic_island.lua)

## 完了条件

- [ ] 既存SketchyBarとの完全な共存
- [ ] 音楽再生情報の動的表示
- [ ] システム情報（音量・明度等）の表示
- [ ] スムーズなアニメーション
- [ ] 設定ファイルでの機能制御
- [ ] 性能への影響最小化

---

**最終更新**: 2025年7月13日  
**作成者**: Claude Code Assistant