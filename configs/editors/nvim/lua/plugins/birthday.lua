-- birthday.nvim — 誕生日のその日、初回 nvim 起動でお祝いを表示する
-- 自作 repo gapul/birthday-tui。lazy の dev 設定(config/lazy.lua)で ~/Developer の
-- ローカル checkout から読まれる(`bday` も同 checkout を PATH 経由で使用)。
return {
  {
    "gapul/birthday-tui",
    lazy = false, -- 起動時にロードして VimEnter チェックを登録
    config = function()
      require('birthday').setup({
        name = 'Yuki',
        birthday = '2004-06-22', -- 毎年 6/22 にお祝い（年齢も自動表示）
        palette = 'dusty',
      })
    end,
  },
}
