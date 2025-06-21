# 🚀 Wezterm設定ガイド

## 📋 キーバインド一覧

### タブ管理
| キー | 動作 |
|------|------|
| `Cmd+T` | 新規タブ作成 |
| `Cmd+W` | タブを閉じる |
| `Ctrl+Tab` | 次のタブ |
| `Ctrl+Shift+Tab` | 前のタブ |

### ペイン操作
| キー | 動作 |
|------|------|
| `Cmd+D` | 水平分割 |
| `Cmd+Shift+D` | 垂直分割 |
| `Cmd+X` | ペインを閉じる |

### ペイン移動
| キー | 動作 |
|------|------|
| `Cmd+Opt+矢印` | ペイン移動（矢印キー） |
| `Cmd+Opt+H/J/K/L` | ペイン移動（Vim風） |

### ペインサイズ調整
| キー | 動作 |
|------|------|
| `Cmd+Ctrl+矢印` | ペインサイズ調整 |

### ワークスペース
| キー | 動作 |
|------|------|
| `Cmd+Shift+N` | 次のワークスペース |
| `Cmd+Shift+P` | 前のワークスペース |
| `Cmd+Shift+W` | ワークスペース選択 |

### その他便利機能
| キー | 動作 |
|------|------|
| `Cmd+Shift+Enter` | フルスクリーン切り替え |
| `Cmd+Shift+R` | 設定リロード |
| `Cmd+Shift+U` | 文字・絵文字選択 |

## 🎨 カスタマイズ設定

### テーマ切り替え
設定は自動でシステムの外観に合わせて切り替わります：
- **ダークモード**: Catppuccin Mocha
- **ライトモード**: Catppuccin Latte

### フォント設定
```lua
config.font = wezterm.font_with_fallback {
  'HackGen Console NF',  -- メインフォント
  'SF Mono',             -- フォールバック1
  'Menlo',               -- フォールバック2
}
config.font_size = 14.0
```

### 背景設定
```lua
config.window_background_opacity = 0.92  -- 透明度
config.window_background_gradient = {
  colors = { '#1a1b26', '#24283b', '#1a1b26' },
  orientation = { Radial = { cx = 0.75, cy = 0.75, radius = 1.25 } },
}
```

## 🔧 トラブルシューティング

### 設定が反映されない
```bash
# 設定ファイルの確認
ls -la ~/.config/wezterm/wezterm.lua

# 設定リロード
# Wezterm内で Cmd+Shift+R を押下
```

### フォントが表示されない
```bash
# フォント確認
wezterm ls-fonts --list-system | grep -i hackgen

# フォントインストール確認
ls ~/Library/Fonts/ | grep -i hackgen
```

### キーバインドが効かない
1. 他のアプリケーションとキーバインドが競合していないか確認
2. macOSのシステム設定でキーボードショートカットを確認
3. 設定ファイルのキーバインド設定を確認

### ワークスペースが動作しない
```bash
# Weztermのバージョン確認
wezterm --version

# 最新版にアップデート
brew upgrade wezterm
```

## 📝 設定ファイル編集

```bash
# 設定ファイル編集
vim configs/terminal/wezterm.lua

# 設定確認
cat configs/terminal/wezterm.lua | head -20
```

## 🌟 追加カスタマイズ例

### 独自のカラースキーム
```lua
config.colors = {
  foreground = '#c0caf5',
  background = '#1a1b26',
  -- 他のカラー設定...
}
```

### カスタムキーバインド追加
```lua
table.insert(config.keys, {
  key = 'k',
  mods = 'CTRL|ALT',
  action = wezterm.action.ClearScrollback 'ScrollbackAndViewport',
})
```

このガイドを参考に、Weztermを最大限活用してください！