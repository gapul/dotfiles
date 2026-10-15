-- SystemVerilog and Tcl (Vivado scripts, .xdc constraints) for the CPU experiment.
-- verible (LSP and formatter) and verilator (lint) come from each project's flake devShell, which
-- config/direnv.lua loads for the file being edited; tclint (tclsp, tclfmt) is a workstation
-- package (nix/home/workstation.nix), since the team's flake does not carry it.
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
        -- verible-verilog-ls only knows the files listed in a file list, so without one,
        -- go-to-definition and references stopped at the open files. The list is written to
        -- nvim's cache (not into the project, which is the team's repository) from every
        -- .sv/.svh/.v/.vh under the project root, fresh on each server start.
        verible = {
          cmd = function(dispatchers, config)
            local root = config.root_dir or vim.fn.getcwd()
            local list = vim.fn.stdpath("cache") .. "/verible/" .. vim.fn.sha256(root):sub(1, 16) .. ".filelist"
            vim.fn.mkdir(vim.fs.dirname(list), "p")
            local files = vim.fs.find(function(name, path)
              return name:match("%.s?vh?$") ~= nil and not path:match("/%.") and not path:match("/build")
            end, { path = root, type = "file", limit = math.huge })
            vim.fn.writefile(files, list)
            return vim.lsp.rpc.start({ "verible-verilog-ls", "--file_list_path=" .. list }, dispatchers, { cwd = root })
          end,
        },
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
        -- verilator comes from a project's devShell; outside one, skip it instead of
        -- failing with ENOENT on every save.
        condition = function()
          return vim.fn.executable("verilator") == 1
        end,
      }
    end,
  },
}
