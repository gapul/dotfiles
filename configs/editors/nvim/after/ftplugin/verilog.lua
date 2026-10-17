-- Same as systemverilog.lua: ' starts a sized literal (4'b1010), so it is not paired.
vim.keymap.set("i", "'", "'", { buffer = true, desc = "Literal ' (no pair)" })
