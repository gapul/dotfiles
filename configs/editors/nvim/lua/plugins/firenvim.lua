if vim.g.started_by_firenvim then
  vim.api.nvim_create_autocmd("UIEnter", {
    callback = function()
      vim.opt.laststatus = 0
      vim.opt.showmode = false
      vim.opt.ruler = false
      vim.opt.showtabline = 0
      vim.opt.cmdheight = 0
      vim.opt.signcolumn = "no"
      vim.opt.number = false
      vim.opt.relativenumber = false
    end,
  })
end

return {
  {
    "glacambre/firenvim",
    lazy = false,
    build = ":call firenvim#install(0)",
    init = function()
      vim.g.firenvim_config = {
        localSettings = {
          [".*"] = {
            takeover = "never",
          },
        },
      }
    end,
  },
  -- firenvim起動時はlualineを無効化（statuslineを再表示してしまうため）
  {
    "nvim-lualine/lualine.nvim",
    cond = function()
      return not vim.g.started_by_firenvim
    end,
  },
  -- bufferlineも同様
  {
    "akinsho/bufferline.nvim",
    cond = function()
      return not vim.g.started_by_firenvim
    end,
  },
}
