-- Modern CLI Tools Integration for Neovim
-- Phase 5: Enhanced terminal workflow integration

local M = {}

-- Utility function to check if command exists
local function command_exists(cmd)
  return vim.fn.executable(cmd) == 1
end

-- LazyGit integration
function M.setup_lazygit()
  if not command_exists('lazygit') then
    return
  end

  -- LazyGit terminal toggle
  vim.api.nvim_create_user_command('LazyGit', function()
    local Terminal = require('toggleterm.terminal').Terminal
    local lazygit = Terminal:new({
      cmd = 'lazygit',
      dir = 'git_dir',
      direction = 'float',
      float_opts = {
        border = 'curved',
        width = function()
          return math.floor(vim.o.columns * 0.9)
        end,
        height = function()
          return math.floor(vim.o.lines * 0.9)
        end,
      },
      on_open = function(term)
        vim.cmd('startinsert!')
        vim.api.nvim_buf_set_keymap(term.bufnr, 'n', 'q', '<cmd>close<CR>', { noremap = true, silent = true })
      end,
      on_close = function()
        vim.cmd('checktime')  -- Refresh file changes
      end,
    })
    lazygit:toggle()
  end, { desc = 'Open LazyGit' })

  -- Key mapping for LazyGit
  vim.keymap.set('n', '<leader>gg', '<cmd>LazyGit<CR>', { desc = 'Open LazyGit', silent = true })
end

-- Yazi file manager integration
function M.setup_yazi()
  if not command_exists('yazi') then
    return
  end

  -- Yazi file manager
  vim.api.nvim_create_user_command('Yazi', function()
    local Terminal = require('toggleterm.terminal').Terminal
    local yazi = Terminal:new({
      cmd = 'yazi',
      direction = 'float',
      float_opts = {
        border = 'curved',
        width = function()
          return math.floor(vim.o.columns * 0.9)
        end,
        height = function()
          return math.floor(vim.o.lines * 0.9)
        end,
      },
      on_open = function(term)
        vim.cmd('startinsert!')
        vim.api.nvim_buf_set_keymap(term.bufnr, 'n', 'q', '<cmd>close<CR>', { noremap = true, silent = true })
      end,
    })
    yazi:toggle()
  end, { desc = 'Open Yazi file manager' })

  -- Key mapping for Yazi
  vim.keymap.set('n', '<leader>fm', '<cmd>Yazi<CR>', { desc = 'Open Yazi file manager', silent = true })
end

-- Bottom system monitor integration
function M.setup_bottom()
  if not command_exists('btm') then
    return
  end

  -- Bottom system monitor
  vim.api.nvim_create_user_command('Bottom', function()
    local Terminal = require('toggleterm.terminal').Terminal
    local bottom = Terminal:new({
      cmd = 'btm',
      direction = 'float',
      float_opts = {
        border = 'curved',
        width = function()
          return math.floor(vim.o.columns * 0.9)
        end,
        height = function()
          return math.floor(vim.o.lines * 0.9)
        end,
      },
      on_open = function(term)
        vim.cmd('startinsert!')
        vim.api.nvim_buf_set_keymap(term.bufnr, 'n', 'q', '<cmd>close<CR>', { noremap = true, silent = true })
      end,
    })
    bottom:toggle()
  end, { desc = 'Open Bottom system monitor' })

  -- Key mapping for Bottom
  vim.keymap.set('n', '<leader>tm', '<cmd>Bottom<CR>', { desc = 'Open system monitor', silent = true })
end

-- Enhanced search integration with ripgrep and fd
function M.setup_search_tools()
  -- Enhanced telescope configuration for modern search tools
  if command_exists('rg') and command_exists('fd') then
    require('telescope').setup({
      defaults = {
        vimgrep_arguments = {
          'rg',
          '--color=never',
          '--no-heading',
          '--with-filename',
          '--line-number',
          '--column',
          '--smart-case',
          '--hidden',
          '--glob=!.git/*',
        },
        file_ignore_patterns = {
          "node_modules/.*",
          "%.git/.*",
          "dist/.*",
          "build/.*",
          "target/.*",
          "%.lock",
        },
      },
      pickers = {
        find_files = {
          find_command = { 'fd', '--type', 'f', '--hidden', '--exclude', '.git' },
        },
        live_grep = {
          additional_args = function()
            return { '--hidden', '--glob=!.git/*' }
          end,
        },
      },
    })

    -- Enhanced search keymaps
    vim.keymap.set('n', '<leader>ff', require('telescope.builtin').find_files, { desc = 'Find files (fd)' })
    vim.keymap.set('n', '<leader>fg', require('telescope.builtin').live_grep, { desc = 'Live grep (rg)' })
    vim.keymap.set('n', '<leader>fb', require('telescope.builtin').buffers, { desc = 'Find buffers' })
    vim.keymap.set('n', '<leader>fh', require('telescope.builtin').help_tags, { desc = 'Find help' })
  end
end

-- Eza and bat integration for terminal commands
function M.setup_file_tools()
  if command_exists('eza') then
    -- Quick file listing in current directory
    vim.api.nvim_create_user_command('EzaTree', function()
      vim.cmd('terminal eza --tree --level=3 --icons --git --group-directories-first')
    end, { desc = 'Show file tree with eza' })
    
    vim.keymap.set('n', '<leader>ft', '<cmd>EzaTree<CR>', { desc = 'File tree (eza)', silent = true })
  end

  if command_exists('bat') then
    -- Use bat for previewing files in floating window
    vim.api.nvim_create_user_command('BatPreview', function()
      local file = vim.fn.expand('<cfile>')
      if file and file ~= '' then
        local cmd = string.format('bat --style=numbers,changes --color=always %s', vim.fn.shellescape(file))
        vim.cmd('terminal ' .. cmd)
      else
        vim.notify('No file under cursor', vim.log.levels.WARN)
      end
    end, { desc = 'Preview file with bat' })
    
    vim.keymap.set('n', '<leader>bp', '<cmd>BatPreview<CR>', { desc = 'Preview with bat', silent = true })
  end
end

-- Setup function to initialize all integrations
function M.setup()
  -- Only setup if toggleterm is available
  local ok, _ = pcall(require, 'toggleterm')
  if not ok then
    vim.notify('toggleterm.nvim is required for modern CLI integration', vim.log.levels.WARN)
    return
  end

  M.setup_lazygit()
  M.setup_yazi()
  M.setup_bottom()
  M.setup_search_tools()
  M.setup_file_tools()

  -- Create Which-Key group for modern CLI tools
  local wk_ok, wk = pcall(require, 'which-key')
  if wk_ok then
    wk.add({
      { '<leader>g', group = 'Git' },
      { '<leader>f', group = 'Find/Files' },
      { '<leader>t', group = 'Terminal/Tools' },
    })
  end

  vim.notify('Modern CLI tools integration loaded', vim.log.levels.INFO)
end

return M