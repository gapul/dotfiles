-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- 未使用の言語プロバイダを無効化（:checkhealth の警告解消 + 起動わずかに高速化）
-- skkeleton(denops)=deno / Supermaven=独自バイナリ で動くため node provider も不要
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_node_provider = 0
vim.g.loaded_python3_provider = 0
