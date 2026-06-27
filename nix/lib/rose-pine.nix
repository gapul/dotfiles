# Rosé Pine (main / dark) — 統一パレットの dark バリアント
#
# ★ テーマ切替は nix/lib/theme.nix の active を変えるだけ (このファイルは触らない)。
# 各ツール設定 (fzf/zellij/sketchybar/lazygit/sioyek/atuin 等) は theme.nix 経由で
# ここの色を生成する。hex は prefix 無し。利用側で "#${c.text}" / "0xff${c.text}" 等に整形。
{
  # ─── palette (hex, prefix無し) ───
  base = "191724"; # 背景 (一番暗い)
  surface = "1f1d2e"; # やや明るい背景 (バー等)
  overlay = "26233a"; # さらに上のレイヤ
  muted = "6e6a86"; # 弱い前景 (灰)
  subtle = "908caa"; # 中間の前景
  text = "e0def4"; # 通常テキスト
  love = "eb6f92"; # 赤/ピンク (エラー・critical)
  gold = "f6c177"; # 黄 (警告)
  rose = "ebbcba"; # ローズ (橙相当)
  pine = "31748f"; # 青
  foam = "9ccfd8"; # シアン (緑相当に流用)
  iris = "c4a7e7"; # 紫
  hlMed = "403d52"; # ハイライト (選択 bg 等)

  # ─── tool theme identifiers (色 hex 以外の切替先) ───
  variant = "dark"; # vim.o.background 等に使う論理種別
  ghosttyTheme = "Rose Pine"; # ghostty 同梱テーマ名
  batTheme = "rose-pine"; # bat/delta の theme 名
  yaziFlavor = "rose-pine"; # yazi flavor 名
}
