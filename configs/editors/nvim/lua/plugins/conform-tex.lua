-- .tex の保存時整形（latexindent / MacTeX 同梱）
return {
  "stevearc/conform.nvim",
  opts = {
    formatters_by_ft = {
      tex = { "latexindent" },
    },
    formatters = {
      latexindent = {
        -- -m: 数式・環境のインデント整形, -l: localSettings.yaml を探す
        prepend_args = { "-m" },
      },
    },
  },
}
