-- Mason を無効化する。LSP サーバもリンタ/フォーマッタも nix(home.packages)が PATH に
-- 供給する単一の実体に統一し、CLI・Neovim・CI のバージョン差(= 整形結果のブレ)を根絶する。
-- 一覧は nix/modules/home/packages.nix。mason-lspconfig が無ければ LazyVim は
-- opts.servers の全サーバを vim.lsp.enable するので、PATH にさえあれば起動する。
return {
  { "mason-org/mason.nvim", enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },
}
