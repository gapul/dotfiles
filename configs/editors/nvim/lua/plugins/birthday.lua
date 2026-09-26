-- birthday.nvim — 誕生日のその日、初回 nvim 起動でお祝いを表示する
-- 自作 repo gapul/birthday-tui。lazy の dev 設定(config/lazy.lua)で ~/Developer の
-- ローカル checkout から読まれる(`bday` も同 checkout を PATH 経由で使用)。
local private_config = vim.fn.expand("~/.config/nvim-private/birthday.lua")
-- Also require the checkout itself: with the dev path missing, lazy prints "Local plugin
-- does not exist" to stdout on every start, and in headless mode that corrupts the stream
-- of anything reading nvim's stdout (Firenvim's native-messaging host, 2026-09-26).
local checkout = vim.fn.expand("~/Developer/github.com/gapul/birthday-tui")

return {
  {
    "gapul/birthday-tui",
    enabled = vim.fn.filereadable(private_config) == 1 and vim.fn.isdirectory(checkout) == 1,
    lazy = false, -- 起動時にロードして VimEnter チェックを登録
    config = function()
      local ok, opts = pcall(dofile, private_config)
      if ok and type(opts) == "table" then
        require("birthday").setup(opts)
      end
    end,
  },
}
