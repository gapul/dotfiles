-- Claude Code Integration Plugin
return {
  {
    "greggh/claude-code.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      require("claude-code").setup({
        window = {
          split_ratio = 0.4,          -- Larger window for better visibility
          position = "botright",       -- Bottom right position
          enter_insert = true,         -- Enter insert mode when opening
          hide_numbers = true,         -- Hide line numbers in Claude window
          hide_signcolumn = true,      -- Hide sign column in Claude window
        },
        command = "claude",            -- Claude Code CLI command
        keymaps = {
          toggle = {
            normal = "<leader>ct",     -- Toggle in normal mode
            terminal = "<C-c>",       -- Toggle from within terminal
          }
        }
      })

      -- Additional keymaps for enhanced workflow
      local keymap = vim.keymap

      -- Claude Code commands
      keymap.set("n", "<leader>cc", ":ClaudeCode<CR>", { desc = "Toggle Claude Code" })
      keymap.set("n", "<leader>cr", ":ClaudeCodeContinue<CR>", { desc = "Continue Claude conversation" })
      keymap.set("n", "<leader>cv", ":ClaudeCodeVerbose<CR>", { desc = "Claude verbose mode" })

      -- Quick Claude interactions
      keymap.set("n", "<leader>cq", function()
        vim.ui.input({ prompt = "Claude query: " }, function(input)
          if input and input ~= "" then
            -- Open Claude and send the query
            vim.cmd("ClaudeCode")
            vim.defer_fn(function()
              vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(input .. "<CR>", true, false, true), "n", false)
            end, 100)
          end
        end)
      end, { desc = "Quick Claude query" })

      -- Send current file to Claude for review
      keymap.set("n", "<leader>cf", function()
        local filename = vim.fn.expand("%:t")
        local filetype = vim.bo.filetype
        if filename ~= "" then
          local prompt = string.format("Please review this %s file (%s) for improvements, bugs, and best practices.", filetype, filename)
          vim.cmd("ClaudeCode")
          vim.defer_fn(function()
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(prompt .. "<CR>", true, false, true), "n", false)
          end, 100)
        else
          vim.notify("No file open", vim.log.levels.WARN)
        end
      end, { desc = "Claude review current file" })

      -- Send visual selection to Claude
      keymap.set("v", "<leader>cs", function()
        -- Get visual selection
        local start_pos = vim.fn.getpos("'<")
        local end_pos = vim.fn.getpos("'>")
        local lines = vim.api.nvim_buf_get_lines(0, start_pos[2]-1, end_pos[2], false)
        
        if start_pos[2] == end_pos[2] then
          -- Single line selection
          local line = lines[1]
          local start_col = start_pos[3]
          local end_col = end_pos[3]
          lines[1] = string.sub(line, start_col, end_col)
        end
        
        local content = table.concat(lines, "\n")
        local filetype = vim.bo.filetype
        
        if content ~= "" then
          local prompt = string.format("Please explain this %s code:\n\n```%s\n%s\n```", filetype, filetype, content)
          vim.cmd("ClaudeCode")
          vim.defer_fn(function()
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(prompt .. "<CR>", true, false, true), "n", false)
          end, 100)
        end
      end, { desc = "Claude explain selection" })

      -- Ask Claude to generate tests for current file
      keymap.set("n", "<leader>cg", function()
        local filename = vim.fn.expand("%:t")
        local filetype = vim.bo.filetype
        if filename ~= "" then
          local prompt = string.format("Please generate comprehensive unit tests for this %s file (%s).", filetype, filename)
          vim.cmd("ClaudeCode")
          vim.defer_fn(function()
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(prompt .. "<CR>", true, false, true), "n", false)
          end, 100)
        else
          vim.notify("No file open", vim.log.levels.WARN)
        end
      end, { desc = "Claude generate tests" })

      -- Ask Claude to document the current file
      keymap.set("n", "<leader>cd", function()
        local filename = vim.fn.expand("%:t")
        local filetype = vim.bo.filetype
        if filename ~= "" then
          local prompt = string.format("Please add comprehensive documentation and comments to this %s file (%s).", filetype, filename)
          vim.cmd("ClaudeCode")
          vim.defer_fn(function()
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(prompt .. "<CR>", true, false, true), "n", false)
          end, 100)
        else
          vim.notify("No file open", vim.log.levels.WARN)
        end
      end, { desc = "Claude document code" })

      -- Ask Claude to optimize the current file
      keymap.set("n", "<leader>co", function()
        local filename = vim.fn.expand("%:t")
        local filetype = vim.bo.filetype
        if filename ~= "" then
          local prompt = string.format("Please optimize this %s file (%s) for performance and readability.", filetype, filename)
          vim.cmd("ClaudeCode")
          vim.defer_fn(function()
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(prompt .. "<CR>", true, false, true), "n", false)
          end, 100)
        else
          vim.notify("No file open", vim.log.levels.WARN)
        end
      end, { desc = "Claude optimize code" })
    end,
  },
}