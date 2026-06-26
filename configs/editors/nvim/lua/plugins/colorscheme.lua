-- 全ツール統一テーマ Rosé Pine (main)。
-- 他ツール (ghostty/yazi/bat/delta/fzf/sketchybar) と配色を揃える。
return {
  { "rose-pine/neovim", name = "rose-pine" },

  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "rose-pine",
    },
  },
}
