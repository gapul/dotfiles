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
      { name = "main", path = "~/obsidian-vault" },
    },

    -- 補完: blink.cmp を使用 ([[ でリンク, # でタグ)
    completion = {
      blink = true,
      nvim_cmp = false,
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

    -- リンクに飛ぶ際 vault 内なら obsidian.nvim で開く
    follow_url_func = function(url)
      vim.fn.jobstart({ "open", url }) -- macOS
    end,
  },
}
