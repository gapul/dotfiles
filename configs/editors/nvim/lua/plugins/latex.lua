-- LaTeX 執筆環境（VimTeX）
-- LazyVim の lang.tex extra をベースに、LuaLaTeX + Skim 向けの上書き設定。
-- エンジンの実体は ~/.latexmkrc（lualatex）で、CLI の latexmk と共通化している。
return {
  {
    "lervag/vimtex",
    lazy = false,
    init = function()
      -- コンパイラ: latexmk を使用（~/.latexmkrc を尊重）
      vim.g.vimtex_compiler_method = "latexmk"
      vim.g.vimtex_compiler_latexmk = {
        out_dir = "",
        callback = 1,
        continuous = 1,
        executable = "latexmk",
        options = {
          "-verbose",
          "-file-line-error",
          "-synctex=1",
          "-interaction=nonstopmode",
        },
      }
      -- 全ファイルで LuaLaTeX を強制（latexmkrc 側と一致）
      vim.g.vimtex_compiler_latexmk_engines = { _ = "-lualatex" }

      -- ビューア: Skim（順方向 SyncTeX。逆方向は Skim 側設定で nvim を呼ぶ）
      vim.g.vimtex_view_method = "skim"
      vim.g.vimtex_view_skim_sync = 1
      -- 自動追従時にSkimへキーボードフォーカスを奪わせない
      vim.g.vimtex_view_skim_activate = 0
      vim.g.vimtex_view_skim_reading_bar = 1

      -- カーソル停止から600ms後、Skimを現在行へSyncTeX追従させる。
      -- CursorMovedを直接同期するとAppleScriptを連打するためdebounceする。
      local skim_sync_group = vim.api.nvim_create_augroup("vimtex_skim_auto_sync", { clear = true })
      vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        group = skim_sync_group,
        pattern = "*.tex",
        callback = function(args)
          local generation = (vim.b[args.buf].vimtex_skim_sync_generation or 0) + 1
          vim.b[args.buf].vimtex_skim_sync_generation = generation
          vim.defer_fn(function()
            if
              vim.api.nvim_buf_is_valid(args.buf)
              and vim.api.nvim_get_current_buf() == args.buf
              and vim.b[args.buf].vimtex_skim_sync_generation == generation
              and vim.fn.exists(":VimtexView") == 2
            then
              vim.cmd("silent! VimtexView")
            end
          end, 600)
        end,
      })

      -- quickfix: 余計な警告で開きすぎないように
      vim.g.vimtex_quickfix_open_on_warning = 0
      vim.g.vimtex_quickfix_ignore_filters = {
        "Underfull",
        "Overfull",
        "Package fontspec Warning",
        "LaTeX Font Warning",
      }

      -- conceal は日本語編集の邪魔になりやすいので控えめに
      vim.g.vimtex_syntax_conceal_disable = 1

      -- K のマッピングは LSP に譲る
      vim.g.vimtex_mappings_disable = { n = { "K" } }
    end,
    keys = {
      { "<localleader>l", "", desc = "+vimtex", ft = "tex" },
    },
  },
}
