# 🚀 Neovim カスタマイズ仕様書

> **現代的で効率的なNeovim開発環境の構築ガイド**

このガイドでは、既存のdotfiles管理システムに統合されたNeovimの最適なカスタマイズ方法を解説します。

## 📁 ディレクトリ構造

```
configs/editors/nvim/
├── init.lua                    # メイン設定ファイル
├── lua/
│   ├── config/
│   │   ├── init.lua           # 基本設定モジュール
│   │   ├── options.lua        # Neovimオプション設定
│   │   ├── keymaps.lua        # キーマッピング
│   │   ├── autocmds.lua       # オートコマンド
│   │   └── lazy_bootstrap.lua # LazyNvimブートストラップ
│   ├── plugins/
│   │   ├── init.lua           # プラグインインデックス
│   │   ├── colorscheme.lua    # カラースキーム設定
│   │   ├── lsp.lua            # LSP設定
│   │   ├── treesitter.lua     # Tree-sitter設定
│   │   ├── telescope.lua      # ファジーファインダー
│   │   ├── nvim-tree.lua      # ファイルエクスプローラー
│   │   ├── completion.lua     # 自動補完
│   │   ├── formatter.lua      # コードフォーマッター
│   │   ├── git.lua            # Git統合
│   │   └── ui.lua             # UI拡張
│   └── utils/
│       ├── init.lua           # ユーティリティ関数
│       └── helpers.lua        # ヘルパー関数
```

## ⚡ プラグインマネージャー

### LazyNvim を採用する理由

1. **遅延読み込み**: プラグインを必要な時にのみ読み込み、起動時間を大幅短縮
2. **宣言的設定**: 直感的なLua設定でプラグインを管理
3. **依存関係管理**: 自動的な依存関係解決
4. **パフォーマンス**: 最適化された読み込み戦略

### LazyNvim設定例

```lua
-- configs/editors/nvim/lua/config/lazy_bootstrap.lua
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)
```

## 🎨 カラースキーム設定

### Catppuccin統合（Weztermとの一貫性）

既存のWezterm設定と統一感を保つため、Catppuccinテーマを使用：

```lua
-- configs/editors/nvim/lua/plugins/colorscheme.lua
return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    config = function()
      require("catppuccin").setup({
        flavour = "mocha", -- latte, frappe, macchiato, mocha
        background = {
          light = "latte",
          dark = "mocha",
        },
        transparent_background = true,
        integrations = {
          cmp = true,
          gitsigns = true,
          nvimtree = true,
          telescope = true,
          treesitter = true,
          mason = true,
          which_key = true,
        },
      })
      vim.cmd.colorscheme "catppuccin"
    end,
  },
}
```

## 🔧 基本設定

### オプション設定

```lua
-- configs/editors/nvim/lua/config/options.lua
local opt = vim.opt

-- 一般設定
opt.number = true           -- 行番号表示
opt.relativenumber = true   -- 相対行番号
opt.signcolumn = "yes"      -- サインカラム常時表示
opt.wrap = false            -- 行の折り返し無効
opt.scrolloff = 8           -- スクロール時の余白
opt.sidescrolloff = 8       -- 横スクロール時の余白

-- インデント設定
opt.tabstop = 2             -- タブ幅
opt.softtabstop = 2         -- ソフトタブ幅
opt.shiftwidth = 2          -- インデント幅
opt.expandtab = true        -- タブをスペースに変換
opt.smartindent = true      -- スマートインデント

-- 検索設定
opt.ignorecase = true       -- 大文字小文字を区別しない
opt.smartcase = true        -- 大文字が含まれる場合は区別
opt.hlsearch = false        -- 検索結果ハイライト無効
opt.incsearch = true        -- インクリメンタル検索

-- UI設定
opt.termguicolors = true    -- 24bit色対応
opt.updatetime = 50         -- CursorHold更新間隔
opt.timeoutlen = 300        -- キーマップタイムアウト
```

### キーマッピング設定

```lua
-- configs/editors/nvim/lua/config/keymaps.lua
local keymap = vim.keymap

-- Leader key設定
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- 基本操作
keymap.set("n", "<leader>pv", vim.cmd.Ex)
keymap.set("v", "J", ":m '>+1<CR>gv=gv")
keymap.set("v", "K", ":m '<-2<CR>gv=gv")

-- ウィンドウ操作
keymap.set("n", "<C-h>", "<C-w>h")
keymap.set("n", "<C-j>", "<C-w>j")
keymap.set("n", "<C-k>", "<C-w>k")
keymap.set("n", "<C-l>", "<C-w>l")

-- バッファ操作
keymap.set("n", "<S-h>", ":bprevious<CR>")
keymap.set("n", "<S-l>", ":bnext<CR>")
keymap.set("n", "<leader>x", ":bdelete<CR>")

-- クイック保存・終了
keymap.set("n", "<leader>w", ":w<CR>")
keymap.set("n", "<leader>q", ":q<CR>")
```

## 🔍 必須プラグイン選定

### 1. LSP設定 (nvim-lspconfig + Mason)

```lua
-- configs/editors/nvim/lua/plugins/lsp.lua
return {
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "williamboman/mason.nvim",
      "williamboman/mason-lspconfig.nvim",
    },
    config = function()
      require("mason").setup()
      require("mason-lspconfig").setup({
        ensure_installed = {
          "lua_ls",
          "tsserver",
          "pyright",
          "rust_analyzer",
          "clangd",
        },
      })
      
      local lspconfig = require("lspconfig")
      local capabilities = require("cmp_nvim_lsp").default_capabilities()
      
      -- 共通設定
      local on_attach = function(client, bufnr)
        local opts = { buffer = bufnr, remap = false }
        vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
        vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
        vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
        vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
      end
      
      -- 各言語サーバー設定
      lspconfig.lua_ls.setup({
        capabilities = capabilities,
        on_attach = on_attach,
        settings = {
          Lua = {
            diagnostics = { globals = { "vim" } },
          },
        },
      })
      
      lspconfig.tsserver.setup({
        capabilities = capabilities,
        on_attach = on_attach,
      })
    end,
  },
}
```

### 2. 自動補完 (nvim-cmp)

```lua
-- configs/editors/nvim/lua/plugins/completion.lua
return {
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-nvim-lua",
      "L3MON4D3/LuaSnip",
      "saadparwaiz1/cmp_luasnip",
      "rafamadriz/friendly-snippets",
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")
      
      require("luasnip.loaders.from_vscode").lazy_load()
      
      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-b>"] = cmp.mapping.scroll_docs(-4),
          ["<C-f>"] = cmp.mapping.scroll_docs(4),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-e>"] = cmp.mapping.abort(),
          ["<CR>"] = cmp.mapping.confirm({ select = true }),
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
          { name = "buffer" },
          { name = "path" },
        }),
      })
    end,
  },
}
```

### 3. ファジーファインダー (Telescope)

```lua
-- configs/editors/nvim/lua/plugins/telescope.lua
return {
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      {
        "nvim-telescope/telescope-fzf-native.nvim",
        build = "make",
      },
    },
    config = function()
      local telescope = require("telescope")
      local actions = require("telescope.actions")
      
      telescope.setup({
        defaults = {
          prompt_prefix = " ",
          selection_caret = " ",
          path_display = { "truncate" },
          mappings = {
            i = {
              ["<C-k>"] = actions.move_selection_previous,
              ["<C-j>"] = actions.move_selection_next,
              ["<C-q>"] = actions.send_selected_to_qflist + actions.open_qflist,
            },
          },
        },
      })
      
      telescope.load_extension("fzf")
      
      -- キーマッピング
      local builtin = require("telescope.builtin")
      vim.keymap.set("n", "<leader>ff", builtin.find_files, {})
      vim.keymap.set("n", "<leader>fg", builtin.live_grep, {})
      vim.keymap.set("n", "<leader>fb", builtin.buffers, {})
      vim.keymap.set("n", "<leader>fh", builtin.help_tags, {})
    end,
  },
}
```

### 4. ファイルエクスプローラー (nvim-tree)

```lua
-- configs/editors/nvim/lua/plugins/nvim-tree.lua
return {
  {
    "nvim-tree/nvim-tree.lua",
    dependencies = {
      "nvim-tree/nvim-web-devicons",
    },
    config = function()
      require("nvim-tree").setup({
        sort_by = "case_sensitive",
        view = {
          width = 30,
        },
        renderer = {
          group_empty = true,
        },
        filters = {
          dotfiles = false,
        },
      })
      
      vim.keymap.set("n", "<leader>e", ":NvimTreeToggle<CR>")
    end,
  },
}
```

### 5. Git統合 (Gitsigns + Fugitive)

```lua
-- configs/editors/nvim/lua/plugins/git.lua
return {
  {
    "lewis6991/gitsigns.nvim",
    config = function()
      require("gitsigns").setup({
        signs = {
          add = { text = "+" },
          change = { text = "~" },
          delete = { text = "_" },
          topdelete = { text = "‾" },
          changedelete = { text = "~" },
        },
      })
    end,
  },
  {
    "tpope/vim-fugitive",
    cmd = { "Git", "Gdiffsplit", "Gread", "Gwrite", "Ggrep", "GMove", "GDelete", "GBrowse", "GRemove", "GRename", "Glgrep", "Gedit" },
  },
}
```

### 6. Tree-sitter (構文ハイライト)

```lua
-- configs/editors/nvim/lua/plugins/treesitter.lua
return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter.configs").setup({
        ensure_installed = {
          "lua",
          "javascript",
          "typescript",
          "python",
          "rust",
          "c",
          "cpp",
          "json",
          "yaml",
          "markdown",
          "bash",
        },
        sync_install = false,
        auto_install = true,
        highlight = {
          enable = true,
          additional_vim_regex_highlighting = false,
        },
        indent = {
          enable = true,
        },
      })
    end,
  },
}
```

### 7. Claude Code統合

```lua
-- configs/editors/nvim/lua/plugins/claude-code.lua
return {
  {
    "greggh/claude-code.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      require("claude-code").setup({
        window = {
          split_ratio = 0.4,
          position = "botright",
          enter_insert = true,
        },
        command = "claude",
        keymaps = {
          toggle = {
            normal = "<leader>ct",
            terminal = "<C-c>",
          }
        }
      })
    end,
  },
}
```

## 🔗 Dotfiles統合

### install.shへの追加

既存の`install.sh`にNeovim設定を追加：

```bash
# DOTFILES_LIST配列に追加
"editors/nvim:$HOME_DIR/.config/nvim"
```

### シンボリックリンク作成

```bash
# 手動での作成例
ln -sf "$PWD/configs/editors/nvim" ~/.config/nvim
```

## 🚀 セットアップ手順

### 1. ディレクトリ構造作成

```bash
mkdir -p configs/editors/nvim/lua/{config,plugins,utils}
```

### 2. 基本設定ファイル作成

```bash
# メイン設定
touch configs/editors/nvim/init.lua

# 基本設定モジュール
touch configs/editors/nvim/lua/config/{init.lua,options.lua,keymaps.lua,autocmds.lua,lazy_bootstrap.lua}

# プラグイン設定
touch configs/editors/nvim/lua/plugins/{init.lua,colorscheme.lua,lsp.lua,completion.lua,telescope.lua,nvim-tree.lua,git.lua,treesitter.lua}
```

### 3. メイン設定ファイル

```lua
-- configs/editors/nvim/init.lua
require("config")
```

### 4. 設定モジュールインデックス

```lua
-- configs/editors/nvim/lua/config/init.lua
require("config.options")
require("config.keymaps")
require("config.autocmds")
require("config.lazy_bootstrap")

require("lazy").setup("plugins")
```

## 🎯 パフォーマンス最適化

### 1. 遅延読み込み設定

```lua
-- プラグインの遅延読み込み例
return {
  {
    "nvim-telescope/telescope.nvim",
    cmd = "Telescope",
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find Files" },
      { "<leader>fg", "<cmd>Telescope live_grep<cr>", desc = "Live Grep" },
    },
  },
}
```

### 2. 起動時間測定

```bash
# 起動時間プロファイリング
nvim --startuptime startup.log +q && cat startup.log
```

## 🧪 設定検証

### 1. ヘルスチェック

```bash
# Neovim内で実行
:checkhealth
```

### 2. LSP動作確認

```bash
# LSP情報確認
:LspInfo
:Mason
```

## 🔧 カスタマイズ例

### 開発言語別設定

```lua
-- configs/editors/nvim/lua/config/autocmds.lua
local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd

-- Python設定
local python_group = augroup("PythonSettings", {})
autocmd("FileType", {
  group = python_group,
  pattern = "python",
  callback = function()
    vim.opt_local.tabstop = 4
    vim.opt_local.shiftwidth = 4
    vim.opt_local.softtabstop = 4
  end,
})

-- JavaScript/TypeScript設定
local js_group = augroup("JSSettings", {})
autocmd("FileType", {
  group = js_group,
  pattern = { "javascript", "typescript", "javascriptreact", "typescriptreact" },
  callback = function()
    vim.opt_local.tabstop = 2
    vim.opt_local.shiftwidth = 2
    vim.opt_local.softtabstop = 2
  end,
})
```

## 🛠️ トラブルシューティング

### よくある問題と解決策

**Q: プラグインが読み込まれない**
```bash
# 解決方法
:Lazy sync
:Lazy clean
```

**Q: LSPが動作しない**
```bash
# 解決方法
:LspInfo
:Mason
:MasonInstall <language-server>
```

**Q: 起動が遅い**
```bash
# プロファイリング実行
nvim --startuptime startup.log
# 遅延読み込み設定を見直す
```

## 📊 設定ファイル管理

### バージョン管理

```bash
# 設定変更の追跡
git add configs/editors/nvim/
git commit -m "Add Neovim configuration"
```

### バックアップ

既存のdotfilesバックアップシステムにより自動的にバックアップされます。

## 🤖 Claude Code統合

### 主要キーマッピング

| キー | 機能 | 説明 |
|------|------|------|
| `<leader>cc` | Claude Code起動 | Claude Codeターミナルを開く |
| `<leader>cr` | 会話継続 | 前回の会話を再開 |
| `<leader>cq` | クイッククエリ | 入力プロンプトでClaude Codeに質問 |
| `<leader>cf` | ファイルレビュー | 現在のファイルをレビュー依頼 |
| `<leader>cs` | 選択範囲説明 | 選択したコードの説明を依頼 |
| `<leader>cg` | テスト生成 | 現在のファイルのテスト生成 |
| `<leader>cd` | ドキュメント生成 | コードドキュメント生成 |
| `<leader>co` | コード最適化 | パフォーマンス最適化提案 |

### 使用例

```vim
" Claude Codeでコードレビューを依頼
<leader>cf

" 選択範囲の説明を求める（Visual mode）
V5j<leader>cs

" 現在のファイルのテスト生成
<leader>cg
```

## 🎉 完成後の機能

- **高速起動**: 遅延読み込みによる最適化
- **統一テーマ**: Weztermとの視覚的一貫性
- **強力なLSP**: 多言語対応の開発環境
- **直感的操作**: Vim風キーバインド
- **Git統合**: シームレスなバージョン管理
- **Claude Code統合**: AI支援による開発効率化
- **拡張性**: プラグインによる機能拡張

---

この仕様書に従って設定することで、既存のdotfiles環境に完全に統合された、現代的で効率的なNeovim開発環境を構築できます。