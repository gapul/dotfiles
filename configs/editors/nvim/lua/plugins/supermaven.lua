-- Supermaven: AI コード補完
-- 個人利用は無料 (約30万トークン/月)
-- セットアップ: :Lazy sync 後に :SupermavenUseFree でメール認証
return {
  "supermaven-inc/supermaven-nvim",
  event = "InsertEnter",
  cmd = {
    "SupermavenStart",
    "SupermavenStop",
    "SupermavenRestart",
    "SupermavenToggle",
    "SupermavenStatus",
    "SupermavenUseFree",
    "SupermavenUsePro",
    "SupermavenLogout",
    "SupermavenShowLog",
    "SupermavenClearLog",
  },
  opts = {
    keymaps = {
      accept_suggestion = "<M-l>",
      clear_suggestion = "<M-q>",
      accept_word = "<M-j>",
    },
    log_level = "info",
    disable_inline_completion = false,
    disable_keymaps = false,
    condition = function()
      -- skkeleton 日本語入力中は補完を抑制
      return vim.b.skkeleton_enabled == true
    end,
  },
  config = function(_, opts)
    require("supermaven-nvim").setup(opts)

    local function update_suggestion_color()
      local color = vim.o.background == "light" and "#9893a5" or "#6e6a86"
      vim.api.nvim_set_hl(0, "SupermavenSuggestion", { fg = color, ctermfg = 244 })
    end

    update_suggestion_color()
    vim.api.nvim_create_autocmd({ "ColorScheme", "OptionSet" }, {
      pattern = { "*", "background" },
      callback = update_suggestion_color,
      desc = "Keep Supermaven ghost text in sync with the system appearance",
    })
  end,
}
