-- Prolog (SWI-Prolog) 学習用最小設定
-- fl_jikken 第10-12回 (論理型プログラミング)
--
-- 前提:
--   * swi-prolog がインストール済 (brew install swi-prolog)
--   * swipl コマンドが PATH にある

return {
  -- (1) Treesitter で .pl のシンタックスハイライト
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "prolog" })
    end,
  },

  -- (2) .pl を Prolog として認識(LazyVim/標準だと perl と曖昧)
  {
    "LazyVim/LazyVim",
    init = function()
      vim.filetype.add({
        extension = {
          pl = "prolog",
          plt = "prolog",
          pro = "prolog",
        },
      })
    end,
  },

  -- (3) <leader>rp で現バッファを swipl で実行
  --   :SwiplLoad で REPL に load も用意
  {
    "folke/which-key.nvim",
    opts = function(_, opts)
      -- keymap
      vim.keymap.set("n", "<leader>rp", function()
        vim.cmd("write")
        vim.cmd("vsplit | terminal swipl " .. vim.fn.expand("%"))
      end, { desc = "Run current Prolog file in swipl" })

      -- ex command: :SwiplLoad で 現ファイルを REPL に load
      vim.api.nvim_create_user_command("SwiplLoad", function()
        vim.cmd("write")
        vim.cmd(string.format("vsplit | terminal swipl -s %s", vim.fn.expand("%")))
      end, { desc = "Open SWI-Prolog REPL and load current file" })

      return opts
    end,
  },
}
