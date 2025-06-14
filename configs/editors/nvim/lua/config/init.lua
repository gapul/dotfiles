-- Configuration Module Index
require("config.options")
require("config.keymaps")
require("config.autocmds")
require("config.lazy_bootstrap")

-- Initialize Lazy.nvim with plugins
require("lazy").setup("plugins")