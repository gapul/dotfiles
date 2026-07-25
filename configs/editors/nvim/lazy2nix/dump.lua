-- Dump lazy.nvim's fully resolved plugin table for lazy2nix.
local out_path = assert(vim.env.LAZY2NIX_DUMP, "LAZY2NIX_DUMP is not set")
local plugins = require("lazy.core.config").plugins
local out = {}

for name, plugin in pairs(plugins) do
  out[#out + 1] = {
    name = name,
    url = plugin.url,
    virtual = plugin.virtual or false,
    version = plugin.version,
    branch = plugin.branch,
    commit = plugin.commit,
    has_build = plugin.build ~= nil,
  }
end

table.sort(out, function(a, b)
  return a.name < b.name
end)

local file = assert(io.open(out_path, "w"))
file:write(vim.json.encode(out))
file:close()
