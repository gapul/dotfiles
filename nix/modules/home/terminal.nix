# Terminal component (ECS: profile). zellij + theme generation + ghostty terminfo.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  c = import ../../lib/theme.nix; # active theme's palette (switch via active in nix/lib/theme.nix)

  # Generate a zellij theme kdl from palette p. Emits both dark/light, tied on the config.kdl
  # side via theme_dark / theme_light to the terminal palette (= ghostty's macOS following).
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

  # Generate tmux's rose-pine status bar from the active palette c.
  # Switch active in palettes.json -> just rebuild follows it, same as zellij.
  mkTmuxTheme = p: ''
    # rose-pine (generated from configs/theme/palettes.json — do not edit by hand)
    set -g status-position top
    set -g status-interval 5
    set -g status-justify left

    set -g status-style               "bg=#${p.base},fg=#${p.subtle}"
    set -g status-left-length 40
    set -g status-right-length 80
    set -g status-left  "#[bg=#${p.pine},fg=#${p.base},bold] #S #[bg=#${p.base},fg=#${p.pine}]#[default] "
    # status-right, left to right:
    #   - PREFIX badge while the prefix key is armed (client_prefix). tmux redraws the status
    #     on client_prefix change, so it appears/disappears in real time (independent of interval).
    #   - 💾 HH:MM = last tmux-resurrect save time, so you can always see it saved without
    #     pressing anything. Read via a script because tmux would strftime-expand %-tokens in
    #     an inline #(); the script keeps the % inside itself. (continuum here has no
    #     #{continuum_status}, so this is the reliable way to surface the last save.)
    set -g status-right "#{?client_prefix,#[bg=#${p.love}#,fg=#${p.base}#,bold] PREFIX #[default] ,}#[fg=#${p.muted}]#(${config.home.homeDirectory}/.config/tmux/resurrect-status.sh) #[fg=#${p.muted}]%Y-%m-%d #[fg=#${p.foam}]%H:%M "

    # inactive / active windows (tabs)
    set -g window-status-format         "#[fg=#${p.muted}] #I #W "
    set -g window-status-current-format "#[bg=#${p.overlay},fg=#${p.iris},bold] #I #W "
    set -g window-status-separator ""
    set -g window-status-activity-style "fg=#${p.gold}"

    # pane border / message / copy mode
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
  # Distribute Ghostty's terminfo to all hosts. If TERM=xterm-ghostty is unknown on an
  # ssh target, ZLE misreads terminal capabilities and input breaks (real damage on macmini 2026-07-19).
  # pkgs.ghostty is darwin unsupported, so vendor an infocmp dump and compile it with tic
  # at activation time.
  # Keep the real data under XDG data and maintain the compat path ~/.terminfo as a symlink
  # (XDG-ify while keeping max compat so ssh targets and GUIs can read it even without TERMINFO_DIRS).
  home.activation.ghosttyTerminfo = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run /bin/mkdir -p "${config.xdg.dataHome}/terminfo"
    run ${pkgs.ncurses}/bin/tic -x -o "${config.xdg.dataHome}/terminfo" ${../../../configs/terminals/ghostty/xterm-ghostty.terminfo}
  '';
  home.file.".terminfo".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.dataHome}/terminfo";

  # symlink dotfiles/configs/* (OS-independent ones only. Mac-only = sketchybar/karabiner go to home/darwin.nix)
  home.file.".config/zellij" = {
    source = ../../../configs/terminals/zellij;
    recursive = true;
  };
  # zellij themes generated from nix/lib/theme.nix (config.kdl references them via theme "rose-pine")
  home.file.".config/zellij/themes/rose-pine.kdl".text = mkZellijTheme "rose-pine" c.dark;
  home.file.".config/zellij/themes/rose-pine-dawn.kdl".text = mkZellijTheme "rose-pine-dawn" c.light;

  # tmux (zellij alternative). symlink tmux.conf and generate both rose-pine variants so tmux
  # can follow the macOS appearance (light/dark) live, like ghostty/nvim/sketchybar do.
  home.file.".config/tmux/tmux.conf".source = ../../../configs/terminals/tmux/tmux.conf;
  home.file.".config/tmux/rose-pine.conf".text = mkTmuxTheme c.dark;
  home.file.".config/tmux/rose-pine-dawn.conf".text = mkTmuxTheme c.light;
  # theme.conf is what tmux.conf sources. On macOS it branches on AppleInterfaceStyle at source
  # time, so it picks the right variant at startup AND whenever the theme-watch agent (see
  # darwin-chrome.nix) re-sources it on an appearance change. Elsewhere there is no OS appearance
  # signal to follow, so it just loads the active palette (switch via active in palettes.json).
  home.file.".config/tmux/theme.conf".text =
    if pkgs.stdenv.isDarwin then
      ''
        if-shell '[ "$(/usr/bin/defaults read -g AppleInterfaceStyle 2>/dev/null)" = "Dark" ]' \
          'source-file -q ~/.config/tmux/rose-pine.conf' \
          'source-file -q ~/.config/tmux/rose-pine-dawn.conf'
      ''
    else
      ''
        source-file -q ~/.config/tmux/${c.active}.conf
      '';

  # Last tmux-resurrect save time for the status bar (see status-right in mkTmuxTheme).
  # Portable stat: BSD (macOS) first, GNU (Linux) fallback. No output if nothing saved yet.
  home.file.".config/tmux/resurrect-status.sh" = {
    executable = true;
    text = ''
      #!/bin/sh
      f="''${XDG_STATE_HOME:-$HOME/.local/state}/tmux/resurrect/last"
      [ -e "$f" ] || exit 0
      t=$(stat -L -f '%Sm' -t '%H:%M' "$f" 2>/dev/null || stat -L -c '%y' "$f" 2>/dev/null | cut -c12-16)
      [ -n "$t" ] && printf '💾 %s' "$t"
    '';
  };

  # tmux plugins (equivalent to zellij's session persistence). Generate a plugins.conf that
  # run-shells store paths without TPM (sourced at the end of tmux.conf).
  #   resurrect: prefix+Ctrl-s save / prefix+Ctrl-r restore (restores pane contents + nvim too)
  #   continuum: auto-save every 15 minutes, auto-restore when the tmux server starts
  home.file.".config/tmux/plugins.conf".text = ''
    # resurrect writes its saves outside XDG (~/.tmux/resurrect) unless told otherwise.
    set -g @resurrect-dir '${config.xdg.stateHome}/tmux/resurrect'
    set -g @resurrect-capture-pane-contents 'on'
    set -g @resurrect-strategy-nvim 'session'
    set -g @continuum-restore 'on'
    set -g @continuum-save-interval '15'
    run-shell ${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect/resurrect.tmux
    run-shell ${pkgs.tmuxPlugins.continuum}/share/tmux-plugins/continuum/continuum.tmux
  '';
  # tmuxp starter layout (equivalent to a zellij layout). Build via `tmuxp load dev`.
  # ~/.config/tmuxp/ becomes a real directory, so you can add your own YAML alongside it.
  home.file.".config/tmuxp/dev.yaml".source = ../../../configs/terminals/tmux/tmuxp/dev.yaml;
}
