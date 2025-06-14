-- Telescope Configuration
return {
  {
    "nvim-telescope/telescope.nvim",
    branch = "0.1.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      {
        "nvim-telescope/telescope-fzf-native.nvim",
        build = "make",
        cond = function()
          return vim.fn.executable("make") == 1
        end,
      },
      "nvim-tree/nvim-web-devicons",
    },
    config = function()
      local telescope = require("telescope")
      local actions = require("telescope.actions")

      telescope.setup({
        defaults = {
          prompt_prefix = " ",
          selection_caret = " ",
          path_display = { "truncate" },
          file_ignore_patterns = {
            "%.git/",
            "node_modules/",
            "%.npm/",
            "__pycache__/",
            "%.pyc",
            "%.pyo",
            "%.exe",
            "%.dll",
            "%.obj",
            "%.o",
            "%.a",
            "%.lib",
            "%.so",
            "%.dylib",
            "%.ncb",
            "%.sdf",
            "%.suo",
            "%.pdb",
            "%.idb",
            "%.DS_Store",
          },
          mappings = {
            i = {
              ["<C-k>"] = actions.move_selection_previous,
              ["<C-j>"] = actions.move_selection_next,
              ["<C-q>"] = actions.send_selected_to_qflist + actions.open_qflist,
              ["<C-x>"] = actions.select_horizontal,
              ["<C-v>"] = actions.select_vertical,
              ["<C-t>"] = actions.select_tab,
              ["<C-u>"] = actions.preview_scrolling_up,
              ["<C-d>"] = actions.preview_scrolling_down,
              ["<PageUp>"] = actions.results_scrolling_up,
              ["<PageDown>"] = actions.results_scrolling_down,
              ["<Tab>"] = actions.toggle_selection + actions.move_selection_worse,
              ["<S-Tab>"] = actions.toggle_selection + actions.move_selection_better,
              ["<C-c>"] = actions.close,
              ["<Down>"] = actions.move_selection_next,
              ["<Up>"] = actions.move_selection_previous,
              ["<CR>"] = actions.select_default,
            },
            n = {
              ["<esc>"] = actions.close,
              ["<CR>"] = actions.select_default,
              ["<C-x>"] = actions.select_horizontal,
              ["<C-v>"] = actions.select_vertical,
              ["<C-t>"] = actions.select_tab,
              ["<Tab>"] = actions.toggle_selection + actions.move_selection_worse,
              ["<S-Tab>"] = actions.toggle_selection + actions.move_selection_better,
              ["<C-q>"] = actions.send_to_qflist + actions.open_qflist,
              ["j"] = actions.move_selection_next,
              ["k"] = actions.move_selection_previous,
              ["H"] = actions.move_to_top,
              ["M"] = actions.move_to_middle,
              ["L"] = actions.move_to_bottom,
              ["<Down>"] = actions.move_selection_next,
              ["<Up>"] = actions.move_selection_previous,
              ["gg"] = actions.move_to_top,
              ["G"] = actions.move_to_bottom,
              ["<C-u>"] = actions.preview_scrolling_up,
              ["<C-d>"] = actions.preview_scrolling_down,
              ["<PageUp>"] = actions.results_scrolling_up,
              ["<PageDown>"] = actions.results_scrolling_down,
              ["?"] = actions.which_key,
            },
          },
        },
        pickers = {
          find_files = {
            hidden = true,
          },
          live_grep = {
            additional_args = function(opts)
              return { "--hidden" }
            end,
          },
        },
        extensions = {
          fzf = {
            fuzzy = true,
            override_generic_sorter = true,
            override_file_sorter = true,
            case_mode = "smart_case",
          },
        },
      })

      -- Enable telescope fzf native, if installed
      pcall(require("telescope").load_extension, "fzf")

      -- Telescope keymaps
      local builtin = require("telescope.builtin")
      vim.keymap.set("n", "<leader>ff", builtin.find_files, { desc = "Find files" })
      vim.keymap.set("n", "<leader>fg", builtin.live_grep, { desc = "Live grep" })
      vim.keymap.set("n", "<leader>fb", builtin.buffers, { desc = "Find buffers" })
      vim.keymap.set("n", "<leader>fh", builtin.help_tags, { desc = "Help tags" })
      vim.keymap.set("n", "<leader>fr", builtin.oldfiles, { desc = "Recent files" })
      vim.keymap.set("n", "<leader>fc", builtin.commands, { desc = "Commands" })
      vim.keymap.set("n", "<leader>fk", builtin.keymaps, { desc = "Keymaps" })
      vim.keymap.set("n", "<leader>fs", builtin.current_buffer_fuzzy_find, { desc = "Search in current buffer" })
      vim.keymap.set("n", "<leader>fd", builtin.diagnostics, { desc = "Diagnostics" })
      vim.keymap.set("n", "<leader>ft", builtin.treesitter, { desc = "Treesitter symbols" })
      vim.keymap.set("n", "<leader>fq", builtin.quickfix, { desc = "Quickfix list" })
      vim.keymap.set("n", "<leader>fl", builtin.loclist, { desc = "Location list" })
      vim.keymap.set("n", "<leader>fj", builtin.jumplist, { desc = "Jump list" })
      vim.keymap.set("n", "<leader>fm", builtin.marks, { desc = "Marks" })
      vim.keymap.set("n", "<leader>fp", builtin.registers, { desc = "Registers" })
      vim.keymap.set("n", "<leader>f/", builtin.search_history, { desc = "Search history" })
      vim.keymap.set("n", "<leader>f:", builtin.command_history, { desc = "Command history" })

      -- Git pickers
      vim.keymap.set("n", "<leader>gf", builtin.git_files, { desc = "Git files" })
      vim.keymap.set("n", "<leader>gc", builtin.git_commits, { desc = "Git commits" })
      vim.keymap.set("n", "<leader>gb", builtin.git_branches, { desc = "Git branches" })
      vim.keymap.set("n", "<leader>gs", builtin.git_status, { desc = "Git status" })

      -- LSP pickers
      vim.keymap.set("n", "<leader>lr", builtin.lsp_references, { desc = "LSP references" })
      vim.keymap.set("n", "<leader>ld", builtin.lsp_definitions, { desc = "LSP definitions" })
      vim.keymap.set("n", "<leader>li", builtin.lsp_implementations, { desc = "LSP implementations" })
      vim.keymap.set("n", "<leader>lt", builtin.lsp_type_definitions, { desc = "LSP type definitions" })
      vim.keymap.set("n", "<leader>ls", builtin.lsp_document_symbols, { desc = "LSP document symbols" })
      vim.keymap.set("n", "<leader>lw", builtin.lsp_workspace_symbols, { desc = "LSP workspace symbols" })
    end,
  },
}