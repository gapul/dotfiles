# Rosé Pine (main) — 全ツール共通パレット (単一ソース)
#
# テーマを変えたい時はこのファイルの hex を差し替えるだけ。
# 各ツール設定 (fzf/zathura/zellij/sketchybar) はここから生成される。
# hex は prefix 無しで持つ。利用側で "#${c.text}" / "0xff${c.text}" 等に整形する。
{
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
}
