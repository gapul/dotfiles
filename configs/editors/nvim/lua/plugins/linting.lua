-- Modern Linting with nvim-lint
return {
  {
    "mfussenegger/nvim-lint",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      local lint = require("lint")

      -- Configure linters by filetype
      lint.linters_by_ft = {
        python = { "ruff", "mypy" },
        javascript = { "eslint_d" },
        typescript = { "eslint_d" },
        javascriptreact = { "eslint_d" },
        typescriptreact = { "eslint_d" },
        vue = { "eslint_d" },
        svelte = { "eslint_d" },
        lua = { "luacheck" },
        bash = { "shellcheck" },
        sh = { "shellcheck" },
        zsh = { "shellcheck" },
        fish = { "fish" },
        dockerfile = { "hadolint" },
        yaml = { "yamllint" },
        json = { "jsonlint" },
        markdown = { "markdownlint" },
        rust = { "cargo" },
        go = { "golangcilint" },
        nix = { "nix" },
        sql = { "sqlfluff" },
      }

      -- Customize linters
      lint.linters.luacheck.args = {
        "--globals", "vim",
        "--no-unused-args",
        "--formatter", "plain",
        "--codes",
        "--ranges",
        "-"
      }

      -- Create autocommand which carries out the actual linting
      -- on the specified events.
      local lint_augroup = vim.api.nvim_create_augroup("lint", { clear = true })
      
      vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
        group = lint_augroup,
        callback = function()
          -- Only run linters for files, not for directories or special buffers
          if vim.bo.buftype == "" and vim.fn.filereadable(vim.fn.expand("%")) == 1 then
            lint.try_lint()
          end
        end,
      })

      -- Manual linting command
      vim.api.nvim_create_user_command("Lint", function()
        lint.try_lint()
      end, { desc = "Trigger linting for current file" })

      -- Get linting status function for statusline integration
      function _G.get_lint_progress()
        local linters = require("lint").get_running()
        if #linters == 0 then
          return "󰦕"
        end
        return "󱉶 " .. table.concat(linters, ", ")
      end
    end,
    keys = {
      {
        "<leader>cl",
        function()
          require("lint").try_lint()
        end,
        desc = "Trigger linting for current file",
      },
    },
  },
}