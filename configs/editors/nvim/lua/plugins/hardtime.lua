-- Vim efficiency improvement plugin
return {
  {
    "m4xshen/hardtime.nvim",
    dependencies = { "MunifTanjim/nui.nvim", "nvim-lua/plenary.nvim" },
    event = "VeryLazy",
    opts = {
      max_time = 1000, -- Maximum time (in milliseconds) to consider key presses as repeated
      max_count = 4,   -- Maximum count of repeated key presses
      disable_mouse = false, -- Disable mouse support
      hint = true,     -- Enable hint messages for better commands
      notification = true, -- Enable notification when you trigger hardtime
      allow_different_key = false, -- Allow different key after a restricted key
      enabled = true,  -- Enable hardtime by default
      resetting_keys = { -- Keys in what modes that reset the count
        ["1"] = { "n", "x" },
        ["2"] = { "n", "x" },
        ["3"] = { "n", "x" },
        ["4"] = { "n", "x" },
        ["5"] = { "n", "x" },
        ["6"] = { "n", "x" },
        ["7"] = { "n", "x" },
        ["8"] = { "n", "x" },
        ["9"] = { "n", "x" },
        ["c"] = { "n" },
        ["C"] = { "n" },
        ["d"] = { "n" },
        ["D"] = { "n" },
        ["x"] = { "n" },
        ["X"] = { "n" },
        ["y"] = { "n" },
        ["Y"] = { "n" },
        ["p"] = { "n" },
        ["P"] = { "n" },
      },
      restricted_keys = { -- Keys in what modes that should be restricted
        ["h"] = { "n", "x" },
        ["j"] = { "n", "x" },
        ["k"] = { "n", "x" },
        ["l"] = { "n", "x" },
        ["-"] = { "n", "x" },
        ["+"] = { "n", "x" },
        ["gj"] = { "n", "x" },
        ["gk"] = { "n", "x" },
        ["<CR>"] = { "n", "x" },
        ["<C-M>"] = { "n", "x" },
        ["<C-N>"] = { "n", "x" },
        ["<C-P>"] = { "n", "x" },
      },
      disabled_keys = { -- Keys in what modes that should be disabled
        ["<Up>"] = { "n", "i", "v" },
        ["<Down>"] = { "n", "i", "v" },
        ["<Left>"] = { "n", "i", "v" },
        ["<Right>"] = { "n", "i", "v" },
      },
      disabled_filetypes = { -- Filetypes in which hardtime should be disabled
        "qf",
        "netrw",
        "NvimTree",
        "lazy",
        "mason",
        "oil",
        "TelescopePrompt",
        "help",
        "alpha",
        "dashboard",
        "lspinfo",
        "Trouble",
        "trouble",
        "toggleterm",
        "neo-tree",
        "notify",
      },
      hints = { -- Hint messages for better commands
        ["k%^"] = {
          message = function()
            return "Use - instead of k^"
          end,
          length = 2,
        },
        ["j%$"] = {
          message = function()
            return "Use + instead of j$"
          end,
          length = 2,
        },
      },
    },
    config = function(_, opts)
      require("hardtime").setup(opts)
      
      -- Command to toggle hardtime
      vim.api.nvim_create_user_command("HardTimeToggle", function()
        require("hardtime").toggle()
      end, { desc = "Toggle hardtime.nvim" })
    end,
    keys = {
      {
        "<leader>uh",
        function()
          require("hardtime").toggle()
        end,
        desc = "Toggle Hardtime",
      },
    },
  },
}