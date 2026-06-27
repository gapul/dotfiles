# Rosé Pine Dawn (light) — 統一パレットの light バリアント
#
# ★ テーマ切替は nix/lib/theme.nix の active を変えるだけ (このファイルは触らない)。
# dark 版 (rose-pine.nix) と同じキー構成・同じ意味付けで色名が 1:1 対応する公式 light 版。
# hex は prefix 無し。利用側で "#${c.text}" / "0xff${c.text}" 等に整形。
{
  # ─── palette (hex, prefix無し) ───
  base = "faf4ed"; # 背景 (一番明るい)
  surface = "fffaf3"; # やや沈んだ背景 (バー等)
  overlay = "f2e9e1"; # さらに上のレイヤ
  muted = "9893a5"; # 弱い前景 (灰)
  subtle = "797593"; # 中間の前景
  text = "575279"; # 通常テキスト
  love = "b4637a"; # 赤/ピンク (エラー・critical)
  gold = "ea9d34"; # 黄 (警告)
  rose = "d7827e"; # ローズ (橙相当)
  pine = "286983"; # 青
  foam = "56949f"; # シアン (緑相当に流用)
  iris = "907aa9"; # 紫
  hlMed = "dfdad9"; # ハイライト (選択 bg 等)

  # ─── tool theme identifiers (色 hex 以外の切替先) ───
  variant = "light"; # vim.o.background 等に使う論理種別
  ghosttyTheme = "Rose Pine Dawn"; # ghostty 同梱テーマ名
  batTheme = "rose-pine-dawn"; # bat/delta の theme 名
  yaziFlavor = "rose-pine-dawn"; # yazi flavor 名
}
