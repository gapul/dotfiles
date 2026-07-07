return {
  {
    "tidalcycles/vim-tidal",
    ft = { "tidal" },
    init = function()
      local livecoding = vim.env.LIVECODING_DIR or vim.fn.expand("~/Developer/github.com/gapul/livecoding")
      vim.g.maplocalleader = vim.g.maplocalleader or ","
      vim.g.tidal_ghci = "ghci"
      vim.g.tidal_target = "terminal"
      vim.g.tidal_boot_fallback = livecoding .. "/tidal/BootTidal.hs"
      vim.g.tidal_sc_enable = 0
    end,
  },
}
