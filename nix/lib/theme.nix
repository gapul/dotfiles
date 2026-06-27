# ★★★ 統一テーマ切替はこのファイルの active を変えるだけ ★★★
#
#   候補:
#     "rose-pine"      … dark  (main)
#     "rose-pine-dawn" … light (dawn)
#
#   変えたら `just rebuild` で全ツール (zellij/sketchybar/borders/lazygit/fzf/
#   sioyek/atuin/bat/delta/ghostty/nvim …) が一斉に追従する。
#
# このファイルは「どのパレットを使うか」を選ぶだけ。色そのものは
# ./rose-pine.nix (dark) / ./rose-pine-dawn.nix (light) 側で定義する。
let
  active = "rose-pine"; # ← 非自動環境(Linux)/フォールバックの既定パレット

  dark = import ./rose-pine.nix;
  light = import ./rose-pine-dawn.nix;
  palettes = {
    "rose-pine" = dark;
    "rose-pine-dawn" = light;
  };
in
# active パレットを top-level に展開しつつ (既存の c.base 等を維持)、
# dark/light 両方も c.dark / c.light で参照可能にする (macOS 外観追従の生成に使う)。
palettes.${active} // { inherit dark light active; }
