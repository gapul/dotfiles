-- birthday.nvim — 誕生日のその日、初回 nvim 起動でお祝いを表示する
-- リポジトリ: ~/ghq/github.com/gapul/birthday-tui （`bday` を PATH に通済み）
return {
  {
    dir = vim.fn.expand('~/ghq/github.com/gapul/birthday-tui'),
    name = 'birthday-tui',
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
