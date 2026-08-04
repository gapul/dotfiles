-- macOS の外観 (ライト/ダーク) に nvim を自動追従させる。
-- rose-pine は background=light のとき自動で dawn (light variant) になるため、
-- background を切り替えて colorscheme を再適用するだけで dark⇔dawn が連動する。
-- 他ツール (ghostty/yazi/bat) と同じく theme.nix の 2 端点 (rose-pine / rose-pine-dawn) に対応。
--
-- OSC 111: 端末背景色が OSC 11 で一度でも上書きされる (クエリ応答のリーク等の事故) と、
-- ghostty はテーマ切替でその背景を塗り替えなくなり「配色だけ切替・背景は前のまま」で読めなくなる。
-- rose-pine は transparency 運用で端末背景=ghostty テーマが常に正なので、切替毎に無条件リセットする。
local function reset_terminal_bg()
  vim.fn.chansend(vim.v.stderr, "\27]111\7")
end

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
        reset_terminal_bg()
      end,
      set_light_mode = function()
        vim.o.background = "light"
        pcall(vim.cmd.colorscheme, "rose-pine") -- light は自動で dawn
        reset_terminal_bg()
      end,
    },
  },
}
