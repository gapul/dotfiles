return {
  {
    "joshuadanpeterson/typewriter.nvim",
    event = "VeryLazy",
    opts = {
      enable_with_zen_mode = true,
      enable_notifications = false,
      keep_cursor_position = true,
    },
    keys = {
      { "<leader>tw", "<cmd>TWEnable<cr>", desc = "Typewriter: ON" },
      { "<leader>tW", "<cmd>TWDisable<cr>", desc = "Typewriter: OFF" },
      { "<leader>tt", "<cmd>TWToggle<cr>", desc = "Typewriter: Toggle" },
      { "<leader>tc", "<cmd>TWCenter<cr>", desc = "Typewriter: Center current line" },
    },
  },
}
