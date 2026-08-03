-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- 未使用の言語プロバイダを無効化（:checkhealth の警告解消 + 起動わずかに高速化）
-- skkeleton(denops)=deno / Supermaven=独自バイナリ で動くため node provider も不要
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_node_provider = 0
vim.g.loaded_python3_provider = 0

-- フロート/補完ポップアップを軽く半透明にして ghostty のブラーに乗せる。
-- 背景そのものの透過は rose-pine の styles.transparency (plugins/colorscheme.lua) 側で行う。
vim.opt.winblend = 10
vim.opt.pumblend = 10

-- 行の折り返し表示（LazyVim デフォルトは wrap=false）
-- linebreak: 英単語の途中で折り返さない / breakindent: 折り返し行もインデント維持
vim.opt.wrap = true
vim.opt.linebreak = true
vim.opt.breakindent = true
