local hydra_url = "http://127.0.0.1:57101/eval"

local function visual_range()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_line = start_pos[2]
  local end_line = end_pos[2]

  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  return start_line, end_line
end

local function lines_to_code(start_line, end_line)
  return table.concat(vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false), "\n")
end

local function post(code)
  if code == "" then
    vim.notify("Hydra: empty code", vim.log.levels.WARN)
    return
  end

  vim.system({ "curl", "-fsS", "-X", "POST", "--data-binary", "@-", hydra_url }, {
    stdin = code,
    text = true,
  }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        vim.notify("Hydra: sent", vim.log.levels.INFO)
      else
        vim.notify("Hydra: " .. (result.stderr ~= "" and result.stderr or "send failed"), vim.log.levels.ERROR)
      end
    end)
  end)
end

vim.api.nvim_create_user_command("HydraLine", function()
  post(vim.api.nvim_get_current_line())
end, {})

vim.api.nvim_create_user_command("HydraBlock", function()
  post(lines_to_code(vim.fn.line("'{"), vim.fn.line("'}")))
end, {})

vim.api.nvim_create_user_command("HydraBuffer", function()
  post(lines_to_code(1, vim.api.nvim_buf_line_count(0)))
end, {})

vim.api.nvim_create_user_command("HydraVisual", function()
  local start_line, end_line = visual_range()
  post(lines_to_code(start_line, end_line))
end, { range = true })

vim.keymap.set("n", "<leader>hl", "<cmd>HydraLine<cr>", { desc = "Hydra line" })
vim.keymap.set("n", "<leader>hb", "<cmd>HydraBlock<cr>", { desc = "Hydra block" })
vim.keymap.set("n", "<leader>hB", "<cmd>HydraBuffer<cr>", { desc = "Hydra buffer" })
vim.keymap.set("x", "<leader>h", "<cmd>HydraVisual<cr>", { desc = "Hydra visual" })

return {}
