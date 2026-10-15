-- blink.cmp: Enter accepts only a candidate that was picked by hand. LazyVim preselects the first
-- candidate and binds Enter to accept, so finishing a line while the menu was open inserted
-- whatever came first (it kept happening while writing SystemVerilog). Now nothing is selected
-- until Tab / Ctrl+n moves into the list; until then Enter is a plain newline.
return {
  {
    "saghen/blink.cmp",
    opts = {
      completion = {
        list = {
          selection = { preselect = false, auto_insert = true },
        },
      },
    },
  },
}
