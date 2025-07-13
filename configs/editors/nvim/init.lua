-- Main Neovim Configuration
-- Initialize core configuration and plugins

-- Set leader key early
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Load configuration modules
require("config")

-- Load modern CLI integration
require("modern-cli-integration")

-- Final setup notification
vim.notify("Neovim configuration loaded successfully", vim.log.levels.INFO)