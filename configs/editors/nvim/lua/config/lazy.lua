local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    -- add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- LazyVim extras (must come before user plugins)
    { import = "lazyvim.plugins.extras.lang.clangd" },
    -- import/override with your plugins
    { import = "plugins" },
  },
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins will load during startup.
    -- If you know what you're doing, you can set this to `true` to have all your custom plugins lazy-loaded by default.
    lazy = false,
    -- It's recommended to leave version=false for now, since a lot the plugin that support versioning,
    -- have outdated releases, which may break your Neovim install.
    version = false, -- always use the latest git commit
    -- version = "*", -- try installing the latest stable version for plugins that support semver
  },
  -- 自作プラグインは ghq(~/Developer) のローカル checkout から読む。
  -- gapul/* は自動でローカル参照になるので、プラグイン spec は普通の "gapul/<repo>" で書ける
  -- (パス直書き不要 → ghq を動かしても spec 側は無修正)。
  -- Windows では ghq の root を ~/Developer に揃えていない環境が多いため
  -- fallback=true で git clone へ自動退避させる (macOS は今までどおり明示エラー)。
  dev = {
    path = "~/Developer/github.com/gapul",
    patterns = { "gapul" },
    fallback = vim.fn.has("mac") ~= 1,
  },
  -- luarocks 不使用なので rocks サポートを無効化（checkhealth の luarocks ERROR 解消）
  rocks = { enabled = false },
  install = { colorscheme = { "rose-pine", "habamax" } },
  checker = {
    enabled = true, -- check for plugin updates periodically
    notify = false, -- notify on update
  }, -- automatically check for plugin updates
  performance = {
    rtp = {
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        -- "matchit",
        -- "matchparen",
        -- "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
