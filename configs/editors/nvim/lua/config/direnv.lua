-- The project's direnv environment (its flake devShell) for whatever file is being edited, the
-- job direnv.vim does, in a few lines. Without it, a project's tools (verible, verilator, tclint
-- for the CPU experiment) were on PATH only when nvim had been started from a shell inside the
-- project; opened from yazi, a launcher or another directory, the LSP and formatter were missing.
--
-- `direnv export json` prints the changes from the current environment to the one for that
-- directory (loading the project's, or unloading it when leaving), so applying it on each
-- directory change keeps nvim's environment in step, as the shell hook does. Registered from
-- options.lua so that it runs before a buffer's filetype, and with it the LSP, is set up.
if vim.fn.executable("direnv") == 0 then
  return
end

local last_dir

local function apply(dir)
  if dir == last_dir or dir == "" or vim.fn.isdirectory(dir) == 0 then
    return
  end
  last_dir = dir
  local res = vim.system({ "direnv", "export", "json" }, { cwd = dir, text = true }):wait()
  if res.code ~= 0 or res.stdout == nil or res.stdout == "" then
    return
  end
  local ok, env = pcall(vim.json.decode, res.stdout)
  if not ok or type(env) ~= "table" then
    return
  end
  for k, v in pairs(env) do
    vim.env[k] = (v ~= vim.NIL) and v or nil
  end
end

vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile", "BufEnter", "DirChanged" }, {
  group = vim.api.nvim_create_augroup("project_direnv", { clear = true }),
  callback = function(ev)
    local name = vim.api.nvim_buf_get_name(ev.buf)
    local dir = (name ~= "" and vim.bo[ev.buf].buftype == "") and vim.fs.dirname(name) or vim.fn.getcwd()
    apply(dir)
  end,
})
