-- 全ツール統一テーマ Rosé Pine (main)。
-- 他ツール (ghostty/yazi/bat/delta/fzf/sketchybar) と配色を揃える。
-- transparent = true で背景を塗らず、ghostty の background-opacity / blur をエディタ内にも通す。
-- フロート/補完の winblend/pumblend は lua/config/options.lua 側で設定。
return {
  {
    "rose-pine/neovim",
    name = "rose-pine",
    opts = {
      styles = {
        transparent = true,
      },
    },
  },

  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "rose-pine",
    },
  },
}
