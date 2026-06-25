return {
  {
    'vim-skk/skkeleton',
    dependencies = { 'vim-denops/denops.vim' },
    event = 'VeryLazy',
    config = function()
      vim.fn['skkeleton#config'] {
        -- XDG: 辞書は ~/.local/share/skk/ 配下 (XDG_DATA_HOME)
        globalDictionaries = {
          '~/.local/share/skk/SKK-JISYO.L',
          '~/.local/share/skk/SKK-JISYO.jinmei',
          '~/.local/share/skk/SKK-JISYO.geo',
          '~/.local/share/skk/SKK-JISYO.station',
          '~/.local/share/skk/SKK-JISYO.propernoun',
        },
        userDictionary = '~/.local/share/skk/skkeleton-user-dict',
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
