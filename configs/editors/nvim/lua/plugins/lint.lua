return {
  "mfussenegger/nvim-lint",
  opts = function(_, opts)
    opts.linters_by_ft = opts.linters_by_ft or {}
    opts.linters_by_ft.markdown = { "textlint" }

    opts.linters = opts.linters or {}
    opts.linters.textlint = {
      cmd = "textlint",
      stdin = true,
      args = {
        "--no-color",
        "--format",
        "json",
        "--config",
        vim.fn.expand("~/.config/textlint/.textlintrc.json"),
        "--stdin",
        "--stdin-filename",
        function()
          return vim.api.nvim_buf_get_name(0)
        end,
      },
      ignore_exitcode = true,
      parser = function(output, _)
        local diagnostics = {}
        if output == nil or output == "" then
          return diagnostics
        end
        local ok, decoded = pcall(vim.json.decode, output)
        if not ok or type(decoded) ~= "table" or not decoded[1] then
          return diagnostics
        end
        for _, msg in ipairs(decoded[1].messages or {}) do
          local lnum = (msg.line or 1) - 1
          local col = (msg.column or 1) - 1
          table.insert(diagnostics, {
            lnum = lnum,
            col = col,
            end_lnum = lnum,
            end_col = col + 1,
            severity = msg.severity == 2 and vim.diagnostic.severity.ERROR
              or vim.diagnostic.severity.WARN,
            source = "textlint",
            code = msg.ruleId,
            message = msg.message,
          })
        end
        return diagnostics
      end,
      condition = function(_)
        return vim.g.autolint ~= false
      end,
    }
  end,
  keys = {
    {
      "<leader>ul",
      function()
        vim.g.autolint = vim.g.autolint == false
        if not vim.g.autolint then
          vim.diagnostic.reset()
        end
        vim.notify("textlint: " .. (vim.g.autolint and "ON" or "OFF"))
      end,
      desc = "Toggle textlint",
    },
    {
      "<leader>cL",
      function()
        require("lint").try_lint()
      end,
      desc = "Lint now",
    },
  },
}
