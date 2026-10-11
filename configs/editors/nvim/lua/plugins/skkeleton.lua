return {
  {
    "vim-skk/skkeleton",
    dependencies = { "vim-denops/denops.vim" },
    event = "VeryLazy",
    config = function()
      -- 辞書は macOS/Linux: ~/.local/share/skk/, Windows: ~/AppData/Local/skk/
      local skk_dir = vim.fn.has("win32") == 1 and "~/AppData/Local/skk" or "~/.local/share/skk"
      vim.fn["skkeleton#config"]({
        globalDictionaries = {
          skk_dir .. "/SKK-JISYO.L",
          skk_dir .. "/SKK-JISYO.jinmei",
          skk_dir .. "/SKK-JISYO.geo",
          skk_dir .. "/SKK-JISYO.station",
          skk_dir .. "/SKK-JISYO.propernoun",
        },
        userDictionary = skk_dir .. "/skkeleton-user-dict",
        eggLikeNewline = true,
        sources = { "skk_dictionary", "skk_server" },
        skkServerHost = "127.0.0.1",
        skkServerPort = 1178,
        skkServerResEnc = "utf-8",
        -- macOS の azooKey skkserv.app は macSKK に合わせて EUC-JP で受ける。Linux 版は EUC-JP の
        -- 要求に応答しないので UTF-8 で送る (nix/home/fcitx5-skk.nix)。
        skkServerReqEnc = vim.fn.has("mac") == 1 and "euc-jp" or "utf-8",
      })
      vim.keymap.set({ "i", "c", "t" }, "<C-j>", "<Plug>(skkeleton-toggle)")
    end,
  },
}
