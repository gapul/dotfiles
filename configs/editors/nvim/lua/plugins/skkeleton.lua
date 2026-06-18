return {
  {
    'vim-skk/skkeleton',
    dependencies = { 'vim-denops/denops.vim' },
    event = 'VeryLazy',
    config = function()
      vim.fn['skkeleton#config'] {
        globalDictionaries = {
          '~/.skk/SKK-JISYO.L',
          '~/.skk/SKK-JISYO.jinmei',
          '~/.skk/SKK-JISYO.geo',
          '~/.skk/SKK-JISYO.station',
          '~/.skk/SKK-JISYO.propernoun',
        },
        userDictionary = '~/.skk/skkeleton-user-dict',
        eggLikeNewline = true,
        sources = { 'skk_dictionary', 'skk_server' },
        skkServerHost = '127.0.0.1',
        skkServerPort = 1178,
        skkServerResEnc = 'utf-8',
        skkServerReqEnc = 'euc-jp',
      }
      vim.keymap.set({ 'i', 'c', 't' }, '<C-j>', '<Plug>(skkeleton-toggle)')
    end,
  },
}
