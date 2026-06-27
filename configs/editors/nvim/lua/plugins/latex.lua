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
      vim.g.vimtex_view_skim_activate = 1
      vim.g.vimtex_view_skim_reading_bar = 1

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
