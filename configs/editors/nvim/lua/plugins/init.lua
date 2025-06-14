-- Plugin Index
-- This file serves as an index for all plugin configurations
-- Individual plugin configurations are loaded from their respective files

return {
  -- Import all plugin configurations
  { import = "plugins.colorscheme" },
  { import = "plugins.lsp" },
  { import = "plugins.completion" },
  { import = "plugins.telescope" },
  { import = "plugins.nvim-tree" },
  { import = "plugins.treesitter" },
  { import = "plugins.git" },
  { import = "plugins.ui" },
}