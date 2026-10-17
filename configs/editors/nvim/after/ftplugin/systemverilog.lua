-- In SystemVerilog ' is the size/base mark of a literal (32'd8, 8'hAA), not a quote, so
-- mini.pairs closing it to '' had to be deleted by hand every time. A buffer-local map wins
-- over mini.pairs' global one, and an ftplugin runs on every FileType whether or not the
-- plugin has loaded yet.
vim.keymap.set("i", "'", "'", { buffer = true, desc = "Literal ' (no pair)" })
