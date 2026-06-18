return {
  "sphamba/smear-cursor.nvim",
  event = "VeryLazy",
  opts = {
    cursor_color = "none",
    legacy_computing_symbols_support = true,
    smear_between_buffers = true,
    smear_between_neighbor_lines = true,
    smear_insert_mode = true,
    stiffness = 0.8,
    trailing_stiffness = 0.5,
    distance_stop_animating = 0.5,
  },
  keys = {
    {
      "<leader>uS",
      function()
        require("smear_cursor").toggle()
      end,
      desc = "Toggle smear cursor",
    },
  },
}
