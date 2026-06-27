-- macOS の外観 (ライト/ダーク) に nvim を自動追従させる。
-- rose-pine は background=light のとき自動で dawn (light variant) になるため、
-- background を切り替えて colorscheme を再適用するだけで dark⇔dawn が連動する。
-- 他ツール (ghostty/yazi/bat) と同じく theme.nix の 2 端点 (rose-pine / rose-pine-dawn) に対応。
return {
  {
    "f-person/auto-dark-mode.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      update_interval = 3000, -- 3秒ごとに AppleInterfaceStyle をポーリング
      set_dark_mode = function()
        vim.o.background = "dark"
        pcall(vim.cmd.colorscheme, "rose-pine") -- dark_variant = main
      end,
      set_light_mode = function()
        vim.o.background = "light"
        pcall(vim.cmd.colorscheme, "rose-pine") -- light は自動で dawn
      end,
    },
  },
}
