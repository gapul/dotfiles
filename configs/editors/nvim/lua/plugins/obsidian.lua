-- obsidian.nvim: Obsidian vault を Neovim から編集
-- メンテ版 obsidian-nvim/obsidian.nvim を使用 (旧 epwalsh/ ではない)
-- 構成: LazyVim + snacks.picker + blink.cmp に合わせて設定
return {
  "obsidian-nvim/obsidian.nvim",
  version = "*",
  ft = "markdown", -- VeryLazy 方針: markdown を開いた時だけロード
  dependencies = { "nvim-lua/plenary.nvim" },
  opts = {
    legacy_commands = false, -- v4.0 で挙動変更。新コマンド体系を使う

    workspaces = {
      { name = "main", path = "~/Documents/notes" },
    },

    -- 補完: v4.0 から組み込みの obsidian-ls LSP が担うため backend 指定は不要
    -- ([[ でリンク, # でタグ)
    completion = {
      min_chars = 2,
    },

    -- picker: LazyVim デフォルトの snacks.picker に合わせる
    picker = {
      name = "snacks.picker",
    },

    -- デイリーノート保存先 (任意で調整)
    daily_notes = {
      folder = "daily",
      date_format = "%Y-%m-%d",
    },

    -- URL を開く処理は v3.18 から vim.ui.open がデフォルト。
    -- vim.ui.open は mac(open)/win/wsl/linux を自動で振り分けるため個別指定は不要。
  },
}
