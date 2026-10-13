-- SystemVerilog and Tcl (Vivado scripts, .xdc constraints) for the CPU experiment.
-- The tools come from each project's flake devShell through direnv, so they are on PATH only
-- inside such a project: verible (LSP and formatter), verilator (lint), tclint (tclsp, tclfmt).
return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "systemverilog", "tcl" })
      vim.treesitter.language.register("tcl", "xdc")
    end,
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        verible = {},
        tclsp = {},
      },
    },
  },
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        systemverilog = { "verible" },
        verilog = { "verible" },
        tcl = { "tclfmt" },
      },
    },
  },
  {
    "mfussenegger/nvim-lint",
    opts = function(_, opts)
      opts.linters_by_ft = opts.linters_by_ft or {}
      opts.linters_by_ft.systemverilog = { "verilator" }
      opts.linters_by_ft.verilog = { "verilator" }
      opts.linters = opts.linters or {}
      -- Tests need --timing for delays; -y src finds the modules a test instantiates
      -- (run from the project root).
      opts.linters.verilator = {
        prepend_args = { "--timing", "-y", "src" },
      }
    end,
  },
}
