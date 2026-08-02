-- 全ツール統一テーマ Rosé Pine (main)。
-- 他ツール (ghostty/yazi/bat/delta/fzf/sketchybar) と配色を揃える。
-- styles.transparency = true で背景を塗らず、ghostty の background-opacity / blur をエディタ内にも通す。
-- (rose-pine のキーは `transparency`。`transparent` は無効キーで黙って無視され Normal.bg が残るので注意)
-- フロート/補完の winblend/pumblend は lua/config/options.lua 側で設定。
return {
  {
    "rose-pine/neovim",
    name = "rose-pine",
    opts = {
      styles = {
        transparency = true,
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
