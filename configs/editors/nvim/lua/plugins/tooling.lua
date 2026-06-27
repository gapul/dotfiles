-- リンタ/フォーマッタの一元管理
-- 共用ツールは nix(home.packages)が PATH に供給する単一の実体に統一する。
-- Mason には入れさせない(ensure_installed から除外)ことで、CLI・Neovim・CI の
-- バージョン差(= 整形結果のブレ)を根絶する。conform / nvim-lint は PATH 上の
-- nix 版バイナリを参照する。Mason は LSP サーバ専用に縮小する。
local nix_managed = {
  "stylua",
  "shfmt",
  "prettier",
  "ruff", -- ruff は LSP も兼ねるが、フォーマッタ/リンタ実体は nix 版を使う
  "markdownlint-cli2",
}

return {
  "mason-org/mason.nvim",
  opts = function(_, opts)
    opts.ensure_installed = vim.tbl_filter(function(tool)
      return not vim.tbl_contains(nix_managed, tool)
    end, opts.ensure_installed or {})
  end,
}
