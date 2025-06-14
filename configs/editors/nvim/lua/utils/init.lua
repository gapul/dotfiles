-- Utility Functions
local M = {}

-- Check if a plugin is loaded
M.is_loaded = function(name)
  local Config = require("lazy.core.config")
  return Config.plugins[name] and Config.plugins[name]._.loaded
end

-- Get highlight group
M.get_highlight = function(name)
  local hl = vim.api.nvim_get_hl_by_name(name, true)
  if hl.link then
    return M.get_highlight(hl.link)
  end
  return hl
end

-- Create augroup
M.augroup = function(name)
  return vim.api.nvim_create_augroup("neovim_" .. name, { clear = true })
end

-- Safe require
M.safe_require = function(module)
  local ok, result = pcall(require, module)
  if not ok then
    vim.notify("Failed to load " .. module, vim.log.levels.ERROR)
    return nil
  end
  return result
end

-- Get root directory
M.get_root = function()
  local root_patterns = { ".git", "lua", "package.json", "Cargo.toml", "go.mod", "pyproject.toml" }
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    return vim.uv.cwd()
  end
  path = vim.fs.dirname(path)
  local root = vim.fs.find(root_patterns, { path = path, upward = true })[1]
  if root then
    return vim.fs.dirname(root)
  end
  return vim.uv.cwd()
end

-- Toggle option
M.toggle = function(option, silent)
  local info = vim.opt_local[option]:get()
  vim.opt_local[option] = not info
  if not silent then
    vim.notify(option .. " " .. (not info and "enabled" or "disabled"))
  end
end

-- Map key
M.map = function(mode, lhs, rhs, opts)
  opts = opts or {}
  opts.silent = opts.silent ~= false
  vim.keymap.set(mode, lhs, rhs, opts)
end

-- Get visual selection
M.get_visual_selection = function()
  vim.cmd('noau normal! "vy"')
  local text = vim.fn.getreg("v")
  vim.fn.setreg("v", {})
  text = string.gsub(text, "\n", "")
  if #text > 0 then
    return text
  else
    return ""
  end
end

-- Float terminal
M.float_term = function(cmd, opts)
  opts = opts or {}
  opts.size = opts.size or { width = 0.9, height = 0.9 }
  opts.dir = opts.dir or M.get_root()
  
  local Terminal = require("toggleterm.terminal").Terminal
  local float_term = Terminal:new({
    cmd = cmd,
    dir = opts.dir,
    direction = "float",
    float_opts = {
      border = "double",
      width = math.floor(vim.o.columns * opts.size.width),
      height = math.floor(vim.o.lines * opts.size.height),
    },
    on_open = function(term)
      vim.cmd("startinsert!")
      vim.api.nvim_buf_set_keymap(term.bufnr, "n", "q", "<cmd>close<CR>", { noremap = true, silent = true })
    end,
    on_close = function()
      vim.cmd("startinsert!")
    end,
  })
  float_term:toggle()
end

-- Check if buffer is empty
M.is_empty_buffer = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return vim.api.nvim_buf_line_count(bufnr) == 1 and vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)[1] == ""
end

-- Get project files
M.get_project_files = function()
  local builtin = require("telescope.builtin")
  local is_inside_work_tree = {}
  
  local cwd = vim.fn.getcwd()
  if is_inside_work_tree[cwd] == nil then
    vim.fn.system("git rev-parse --is-inside-work-tree")
    is_inside_work_tree[cwd] = vim.v.shell_error == 0
  end

  if is_inside_work_tree[cwd] then
    builtin.git_files({ show_untracked = true })
  else
    builtin.find_files()
  end
end

return M