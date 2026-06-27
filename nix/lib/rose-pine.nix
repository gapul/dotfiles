# Rosé Pine (dark) — palette は configs/theme/palettes.json から読む (SSO)。
# Windows 側 (nix を使わない) からも同じ palette を参照したいので JSON を
# 真実 source にした。
#
# 編集する時は configs/theme/palettes.json の palettes."rose-pine" を変更。
# このファイルは変更不要。
(builtins.fromJSON (builtins.readFile ../../configs/theme/palettes.json)).palettes."rose-pine"
