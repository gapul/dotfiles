# Neovim クイックスタート

> ⚡ **5分でNeovimを使い始める最小設定**

## 🚀 即座使用開始

### 基本コマンド
```bash
# Neovim起動
nvim

# ファイル編集
nvim filename.txt

# 設定確認
nvim --version
```

### 必須キーバインド
| キー | 動作 | 用途 |
|------|------|------|
| `i` | 挿入モード | テキスト入力 |
| `Esc` | ノーマルモード | コマンド実行 |
| `:w` | 保存 | ファイル保存 |
| `:q` | 終了 | Neovim終了 |
| `:wq` | 保存して終了 | 作業完了 |

### LSP (言語サーバー)
```bash
# 自動セットアップ (dotfiles適用時)
# - TypeScript/JavaScript
# - Python  
# - Rust
# - Go
# - Lua
```

## 🔧 基本カスタマイズ

### プラグイン確認
```vim
:Lazy                   " プラグインマネージャー
:Mason                  " LSPマネージャー
:Telescope find_files   " ファイル検索
```

### 設定ファイル場所
- メイン設定: `~/.config/nvim/init.lua`
- プラグイン: `~/.config/nvim/lua/plugins/`
- キーマップ: `~/.config/nvim/lua/config/keymaps.lua`

## 📚 次のステップ

- **詳細設定**: [comprehensive/NEOVIM_ADVANCED_CONFIG.md](../comprehensive/NEOVIM_ADVANCED_CONFIG.md)
- **プラグイン**: [comprehensive/NEOVIM_PLUGIN_GUIDE.md](../comprehensive/NEOVIM_PLUGIN_GUIDE.md)

*設定は自動適用済み - すぐに使用開始できます*
