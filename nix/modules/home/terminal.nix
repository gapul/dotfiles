# Terminal component (ECS: profile)。zellij + テーマ生成 + ghostty terminfo。
{
  config,
  pkgs,
  lib,
  ...
}:
let
  c = import ../../lib/theme.nix; # アクティブテーマのパレット (切替は nix/lib/theme.nix の active)

  # zellij テーマ kdl を palette p から生成。dark/light 両方を吐き、config.kdl 側の
  # theme_dark / theme_light で端末パレット (= ghostty の macOS 追従) に連動させる。
  mkZellijTheme = name: p: ''
    themes {
        ${name} {
            fg "#${p.text}"
            bg "#${p.base}"
            black "#${p.overlay}"
            red "#${p.love}"
            green "#${p.foam}"
            yellow "#${p.gold}"
            blue "#${p.pine}"
            magenta "#${p.iris}"
            cyan "#${p.foam}"
            white "#${p.text}"
            orange "#${p.rose}"
        }
    }
  '';
in
{
  # Ghostty の terminfo を全ホストへ配布。ssh 先で TERM=xterm-ghostty が未知だと
  # ZLE が端末能力を誤解して入力が壊れる (macmini で実害あり 2026-07-19)。
  # pkgs.ghostty は darwin unsupported のため infocmp ダンプを vendoring して
  # activation 時に tic でコンパイルする。
  # 実データは XDG data 配下に置き、互換パス ~/.terminfo は symlink で維持する
  # (ssh 先や GUI が TERMINFO_DIRS 無しでも読める最大互換を保ったまま XDG 化)。
  home.activation.ghosttyTerminfo = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run /bin/mkdir -p "${config.xdg.dataHome}/terminfo"
    run ${pkgs.ncurses}/bin/tic -x -o "${config.xdg.dataHome}/terminfo" ${../../../configs/terminals/ghostty/xterm-ghostty.terminfo}
  '';
  home.file.".terminfo".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.dataHome}/terminfo";

  # dotfiles/configs/* を symlink (OS 非依存なものだけ。Mac 専用 = aerospace/sketchybar/karabiner は home/darwin.nix へ)
  home.file.".config/zellij" = {
    source = ../../../configs/terminals/zellij;
    recursive = true;
  };
  # zellij テーマは nix/lib/theme.nix から生成 (config.kdl は theme "rose-pine" で参照)
  home.file.".config/zellij/themes/rose-pine.kdl".text = mkZellijTheme "rose-pine" c.dark;
  home.file.".config/zellij/themes/rose-pine-dawn.kdl".text = mkZellijTheme "rose-pine-dawn" c.light;
}
