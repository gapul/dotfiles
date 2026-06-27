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
    color = {
      suggestion_color = "#6e6a86", -- Rosé Pine muted (ghost text)
      cterm = 244,
    },
    log_level = "info",
    disable_inline_completion = false,
    disable_keymaps = false,
    condition = function()
      -- skkeleton 日本語入力中は補完を抑制
      return vim.b.skkeleton_enabled == true
    end,
  },
}
