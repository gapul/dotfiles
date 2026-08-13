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

-- macOS 以外では読み込まない。このプラグインは OS に外観を尋ねる作りで、Linux では
-- xdg-desktop-portal (org.freedesktop.appearance) を叩く。nssh 先のような headless の
-- サーバには portal が居らず、dbus-send が NoReply を返す。すると interval.lua の
-- parse_query_response は stderr が空でない場合 nil を返すため set_dark_mode /
-- set_light_mode はどちらも一度も呼ばれず、fallback すら効かない。残るのは応答の来ない
-- dbus-monitor が nvim ごとに常駐することだけなので、素直に切る。
--
-- 代わりにリモートでは Neovim 本体の background 自動判定に任せる。起動時に OSC 11 で
-- 端末へ背景色を尋ね (:h 'background' の "if it can detect the background color")、
-- 0.11 からは端末のテーマ更新通知を受けるたびに再問い合わせして 'background' を更新する
-- (:h news-0.11 の TUI の項)。応答するのは接続元の ghostty なので、母艦のライト/ダークが
-- そのまま効く — theme-remote.conf の ANSI 化や Claude Code の theme=auto と同じ
-- 「色を決めるのはクライアント端末」という筋。
--
-- 多重化ツールの内側では OSC 11 に答えるのは tmux / herdr 自身になるが、どちらも外側の
-- 端末へ問い合わせた結果をそのまま中継することを 2026-08 に実測した (偽端末から light を
-- 返すと、ペイン内は #faf4ed を受け取る)。よって nssh + herdr でも起動時の判定は効く。
--   - tmux 3.6a: 起動時の OSC 11 応答に加え、CSI ?997;Nn でテーマ種別を報告し、
--                途中の切替も 2031 通知としてペインへ中継する (3.4 は応答のみ)
--   - herdr    : 0.8.0 から同等 (0.7.5 は起動時の応答だけで、途中の切替は届かない)
-- どちらも COLORFGBG は設定しないので、判定経路は OSC 11 の一本。
--
-- 未解決が 1 点。擬似端末から nvim へ直接 OSC 11 応答 (light) を返す試験では、問い合わせは
-- 飛ぶのに &background が dark のままだった。上記のとおり中継側は正しいので、原因は nvim 側
-- か試験側にある。実機 (ghostty + nssh) で light に転ばない場合はここを調べ直すこと。
-- vim.uv は 0.10 から。プラグイン本体と同じく vim.loop へ落とす。
local is_macos = (vim.uv or vim.loop).os_uname().sysname == "Darwin"

return {
  {
    "f-person/auto-dark-mode.nvim",
    cond = is_macos,
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
