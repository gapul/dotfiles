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

  # tmux の rose-pine ステータスバーを active パレット c から生成。
  # active を palettes.json で切替 → just rebuild で zellij 同様に追従する。
  mkTmuxTheme = p: ''
    # rose-pine (generated from configs/theme/palettes.json — 手で編集しない)
    set -g status-position top
    set -g status-interval 5
    set -g status-justify left

    set -g status-style               "bg=#${p.base},fg=#${p.subtle}"
    set -g status-left-length 40
    set -g status-right-length 80
    set -g status-left  "#[bg=#${p.pine},fg=#${p.base},bold] #S #[bg=#${p.base},fg=#${p.pine}]#[default] "
    set -g status-right "#[fg=#${p.muted}]%Y-%m-%d #[fg=#${p.foam}]%H:%M "

    # 非アクティブ / アクティブなウィンドウ(タブ)
    set -g window-status-format         "#[fg=#${p.muted}] #I #W "
    set -g window-status-current-format "#[bg=#${p.overlay},fg=#${p.iris},bold] #I #W "
    set -g window-status-separator ""
    set -g window-status-activity-style "fg=#${p.gold}"

    # ペイン枠 / メッセージ / コピーモード
    set -g pane-border-style        "fg=#${p.overlay}"
    set -g pane-active-border-style "fg=#${p.pine}"
    set -g message-style            "bg=#${p.overlay},fg=#${p.text}"
    set -g message-command-style    "bg=#${p.overlay},fg=#${p.text}"
    set -g mode-style               "bg=#${p.hlMed},fg=#${p.text}"
    set -g display-panes-active-colour "#${p.iris}"
    set -g display-panes-colour        "#${p.muted}"
    set -g clock-mode-colour           "#${p.foam}"
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

  # tmux (zellij 代替)。tmux.conf を symlink し、rose-pine テーマを active パレットから生成。
  # tmux は zellij のような端末追従の dark/light 切替を持たないため active パレット c を採用
  # (palettes.json の active 切替 → just rebuild で追従、が SSOT)。
  home.file.".config/tmux/tmux.conf".source = ../../../configs/terminals/tmux/tmux.conf;
  home.file.".config/tmux/rose-pine.conf".text = mkTmuxTheme c;
}
