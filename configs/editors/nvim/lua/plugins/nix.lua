-- Nix language support. nixd, nixfmt, statix and deadnix are installed declaratively by
-- Home Manager.
return {
  {
    "mfussenegger/nvim-lint",
    opts = function(_, opts)
      opts.linters_by_ft = opts.linters_by_ft or {}
      opts.linters_by_ft.nix = { "statix", "deadnix" }
    end,
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        nixd = {
          settings = {
            nixd = {
              formatting = {
                command = { "nixfmt" },
              },
            },
          },
        },
      },
    },
  },
}
