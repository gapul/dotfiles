-- Autocommands Configuration
local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd

-- Highlight on yank
local highlight_group = augroup("YankHighlight", {})
autocmd("TextYankPost", {
  group = highlight_group,
  pattern = "*",
  callback = function()
    vim.highlight.on_yank()
  end,
})

-- Remove whitespace on save
local trim_whitespace_group = augroup("TrimWhitespace", {})
autocmd("BufWritePre", {
  group = trim_whitespace_group,
  pattern = "*",
  command = "%s/\\s\\+$//e",
})

-- Auto format on save for specific file types
local format_group = augroup("FormatOnSave", {})
autocmd("BufWritePre", {
  group = format_group,
  pattern = { "*.lua", "*.js", "*.ts", "*.jsx", "*.tsx", "*.py", "*.rs", "*.go" },
  callback = function()
    vim.lsp.buf.format({ async = false })
  end,
})

-- Language-specific settings
local python_group = augroup("PythonSettings", {})
autocmd("FileType", {
  group = python_group,
  pattern = "python",
  callback = function()
    vim.opt_local.tabstop = 4
    vim.opt_local.shiftwidth = 4
    vim.opt_local.softtabstop = 4
    vim.opt_local.colorcolumn = "88"
  end,
})

local js_group = augroup("JSSettings", {})
autocmd("FileType", {
  group = js_group,
  pattern = { "javascript", "typescript", "javascriptreact", "typescriptreact" },
  callback = function()
    vim.opt_local.tabstop = 2
    vim.opt_local.shiftwidth = 2
    vim.opt_local.softtabstop = 2
  end,
})

local go_group = augroup("GoSettings", {})
autocmd("FileType", {
  group = go_group,
  pattern = "go",
  callback = function()
    vim.opt_local.tabstop = 4
    vim.opt_local.shiftwidth = 4
    vim.opt_local.softtabstop = 4
    vim.opt_local.expandtab = false
  end,
})

-- Auto close NvimTree if it's the last window
local nvim_tree_group = augroup("NvimTreeAutoClose", {})
autocmd("QuitPre", {
  group = nvim_tree_group,
  callback = function()
    local tree_wins = {}
    local floating_wins = {}
    local wins = vim.api.nvim_list_wins()
    for _, w in ipairs(wins) do
      local bufname = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w))
      if bufname:match("NvimTree_") ~= nil then
        table.insert(tree_wins, w)
      end
      if vim.api.nvim_win_get_config(w).relative ~= '' then
        table.insert(floating_wins, w)
      end
    end
    if 1 == #wins - #floating_wins - #tree_wins then
      for _, w in ipairs(tree_wins) do
        vim.api.nvim_win_close(w, true)
      end
    end
  end
})

-- Restore cursor position
local restore_cursor_group = augroup("RestoreCursor", {})
autocmd("BufReadPost", {
  group = restore_cursor_group,
  pattern = "*",
  callback = function()
    local line = vim.fn.line("'\"")
    if line > 1 and line <= vim.fn.line("$") and vim.bo.filetype ~= "commit" then
      vim.cmd('normal! g`"')
    end
  end,
})

-- Auto create directories
local auto_mkdir_group = augroup("AutoMkdir", {})
autocmd("BufWritePre", {
  group = auto_mkdir_group,
  pattern = "*",
  callback = function()
    local dir = vim.fn.expand("<afile>:p:h")
    if vim.fn.isdirectory(dir) == 0 then
      vim.fn.mkdir(dir, "p")
    end
  end,
})