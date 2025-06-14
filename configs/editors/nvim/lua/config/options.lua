-- Neovim Options Configuration
local opt = vim.opt

-- General Settings
opt.number = true           -- Show line numbers
opt.relativenumber = true   -- Show relative line numbers
opt.signcolumn = "yes"      -- Always show sign column
opt.wrap = false            -- Disable line wrapping
opt.scrolloff = 8           -- Minimal number of screen lines to keep above and below the cursor
opt.sidescrolloff = 8       -- Minimal number of screen columns to keep to the left and right of the cursor

-- Indentation Settings
opt.tabstop = 2             -- Number of spaces tabs count for
opt.softtabstop = 2         -- Number of spaces tabs count for while editing
opt.shiftwidth = 2          -- Size of an indent
opt.expandtab = true        -- Use spaces instead of tabs
opt.smartindent = true      -- Insert indents automatically

-- Search Settings
opt.ignorecase = true       -- Ignore case in search patterns
opt.smartcase = true        -- Override ignorecase if search contains capitals
opt.hlsearch = false        -- Don't highlight search results
opt.incsearch = true        -- Show search matches as you type

-- UI Settings
opt.termguicolors = true    -- True color support
opt.updatetime = 50         -- Faster completion (4000ms default)
opt.timeoutlen = 300        -- Time to wait for a mapped sequence to complete
opt.clipboard = "unnamedplus" -- Use system clipboard
opt.mouse = "a"             -- Enable mouse mode
opt.cursorline = true       -- Highlight current line
opt.colorcolumn = "80"      -- Show column at 80 characters

-- File Settings
opt.backup = false          -- Don't create backup files
opt.writebackup = false     -- Don't create writebackup files
opt.swapfile = false        -- Don't create swap files
opt.undofile = true         -- Save undo history

-- Window Settings
opt.splitbelow = true       -- Force all horizontal splits to go below current window
opt.splitright = true       -- Force all vertical splits to go to the right of current window

-- Folding
opt.foldmethod = "expr"
opt.foldexpr = "nvim_treesitter#foldexpr()"
opt.foldenable = false      -- Don't fold by default