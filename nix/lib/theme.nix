# ★★★ 統一テーマ切替は configs/theme/palettes.json の "active" を変えるだけ ★★★
#
#   候補:
#     "rose-pine"      … dark  (main)
#     "rose-pine-dawn" … light (dawn)
#
#   変えたら:
#     - Mac/Linux: `just rebuild` で全 nix 管理ツール (zellij/sketchybar/borders/
#       lazygit/fzf/sioyek/atuin/bat/delta/ghostty/nvim …) が一斉に追従
#     - Windows : `just win-theme` で zebar/glazewm/WT/wezterm が一斉に追従
#   palettes.json を SSO とすることで Mac/Linux/WSL/Windows で同じ active が
#   共有される (旧来は theme.nix と palettes.json に active が二重定義だった)。
#
# 色そのものは configs/theme/palettes.json で palettes."<name>" として保管。
let
  data = builtins.fromJSON (builtins.readFile ../../configs/theme/palettes.json);
  inherit (data) active;
  dark = data.palettes."rose-pine";
  light = data.palettes."rose-pine-dawn";
  palettes = {
    "rose-pine" = dark;
    "rose-pine-dawn" = light;
  };
in
# active パレットを top-level に展開しつつ (既存の c.base 等を維持)、
# dark/light 両方も c.dark / c.light で参照可能にする (macOS 外観追従の生成に使う)。
palettes.${active} // { inherit dark light active; }
