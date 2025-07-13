-- LSP Configuration
return {
  -- LSP Configuration
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      "williamboman/mason.nvim",
      "williamboman/mason-lspconfig.nvim",
      "hrsh7th/cmp-nvim-lsp",
    },
    config = function()
      -- Mason setup
      require("mason").setup({
        ui = {
          border = "rounded",
          icons = {
            package_installed = "✓",
            package_pending = "➜",
            package_uninstalled = "✗",
          },
        },
      })

      -- Mason-LSPConfig setup
      require("mason-lspconfig").setup({
        ensure_installed = {
          "lua_ls",
          "tsserver",
          "pyright",
          "rust_analyzer",
          "clangd",
          "gopls",
          "jsonls",
          "yamlls",
          "bashls",
        },
        automatic_installation = true,
      })

      local lspconfig = require("lspconfig")
      local capabilities = require("cmp_nvim_lsp").default_capabilities()

      -- Global diagnostic configuration
      vim.diagnostic.config({
        virtual_text = {
          prefix = "●",
        },
        signs = true,
        underline = true,
        update_in_insert = false,
        severity_sort = true,
        float = {
          border = "rounded",
          source = "always",
        },
      })

      -- LSP signs
      local signs = { Error = " ", Warn = " ", Hint = " ", Info = " " }
      for type, icon in pairs(signs) do
        local hl = "DiagnosticSign" .. type
        vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = hl })
      end

      -- Common on_attach function
      local on_attach = function(client, bufnr)
        local opts = { buffer = bufnr, remap = false }

        -- LSP keymaps
        vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
        vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
        vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
        vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts)
        vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, opts)
        vim.keymap.set("n", "<leader>wa", vim.lsp.buf.add_workspace_folder, opts)
        vim.keymap.set("n", "<leader>wr", vim.lsp.buf.remove_workspace_folder, opts)
        vim.keymap.set("n", "<leader>wl", function()
          print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
        end, opts)
        vim.keymap.set("n", "<leader>D", vim.lsp.buf.type_definition, opts)
        vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
        vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts)
        vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
        vim.keymap.set("n", "<leader>f", function()
          vim.lsp.buf.format({ async = true })
        end, opts)

        -- Diagnostic keymaps
        vim.keymap.set("n", "<leader>e", vim.diagnostic.open_float, opts)
        vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)
        vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts)
        vim.keymap.set("n", "<leader>dl", vim.diagnostic.setloclist, opts)
      end

      -- Language server configurations
      local servers = {
        lua_ls = {
          settings = {
            Lua = {
              runtime = { version = "LuaJIT" },
              diagnostics = {
                globals = { "vim" },
              },
              workspace = {
                checkThirdParty = false,
                library = {
                  [vim.fn.expand("$VIMRUNTIME/lua")] = true,
                  [vim.fn.stdpath("config") .. "/lua"] = true,
                },
              },
              telemetry = { enable = false },
            },
          },
        },
        tsserver = {},
        pyright = {
          settings = {
            python = {
              analysis = {
                typeCheckingMode = "basic",
              },
            },
          },
        },
        rust_analyzer = {
          settings = {
            ["rust-analyzer"] = {
              cargo = {
                allFeatures = true,
              },
            },
          },
        },
        clangd = {},
        gopls = {},
        jsonls = {},
        yamlls = {},
        bashls = {},
      }

      -- Setup language servers
      for server, config in pairs(servers) do
        config.capabilities = capabilities
        config.on_attach = on_attach
        lspconfig[server].setup(config)
      end
    end,
  },

  -- Mason Tool Installer
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = {
      "williamboman/mason.nvim",
      "williamboman/mason-lspconfig.nvim",
    },
    config = function()
      -- Conditional setup to avoid package errors
      local ok, mason_tool_installer = pcall(require, "mason-tool-installer")
      if ok then
        mason_tool_installer.setup({
          ensure_installed = {
            -- LSP servers (handled by mason-lspconfig)
            
            -- Formatters (for conform.nvim)
            "stylua",      -- Lua formatter
            "black",       -- Python formatter  
            "isort",       -- Python import sorter
            "prettier",    -- JS/TS/JSON/YAML/MD formatter
            "prettierd",   -- Faster prettier daemon
            "shfmt",       -- Shell script formatter
            "rustfmt",     -- Rust formatter
            "gofmt",       -- Go formatter
            "goimports",   -- Go import formatter
            "nixpkgs-fmt", -- Nix formatter
            "taplo",       -- TOML formatter
            
            -- Linters (for nvim-lint)
            "shellcheck",     -- Shell script linter
            "eslint_d",       -- Fast ESLint daemon
            "luacheck",       -- Lua linter
            "ruff",           -- Fast Python linter/formatter
            "mypy",           -- Python type checker
            "hadolint",       -- Dockerfile linter
            "yamllint",       -- YAML linter
            "jsonlint",       -- JSON linter
            "markdownlint",   -- Markdown linter
            "golangci-lint",  -- Go linter
            "sqlfluff",       -- SQL linter
          },
          auto_update = false,
          run_on_start = false, -- Manual installation to avoid errors
        })
        
        vim.notify("Mason tool installer configured", vim.log.levels.INFO)
      else
        vim.notify("Mason tool installer not available", vim.log.levels.WARN)
      end
    end,
  },
}