# Terminal component (ECS: profile). tmux + theme generation + ghostty terminfo.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  c = import ../../lib/theme.nix; # active theme's palette (switch via active in nix/lib/theme.nix)

  # Generate tmux's rose-pine status bar from the active palette c.
  # Switch active in palettes.json -> just rebuild follows it, same as the other themed tools.
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
  # tmux: symlink tmux.conf and generate both rose-pine variants so tmux
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

  # Dump a pane's scrollback and open it in the editor (bound to prefix+e in tmux.conf).
  # This is zellij's EditScrollback. It lives in a script because the quoting for a temp file
  # plus a new-window command does not survive being written inline in tmux.conf.
  home.file.".config/tmux/scrollback-edit.sh" = {
    executable = true;
    text = ''
      #!/bin/sh
      # $1: the pane id to capture (tmux passes #{pane_id})
      set -eu
      f=$(mktemp -t tmux-scrollback)
      tmux capture-pane -p -S - -t "$1" >"$f"
      tmux new-window -n scrollback "''${EDITOR:-nvim} '$f'; rm -f '$f'"
    '';
  };

  # tmux plugins. Generate a plugins.conf that
  # run-shells store paths without TPM (sourced at the end of tmux.conf).
  #   resurrect: prefix+Ctrl-s save / prefix+Ctrl-r restore (restores pane contents + nvim too)
  #   continuum: auto-save every minute, auto-restore when the tmux server starts
  home.file.".config/tmux/plugins.conf".text = ''
    # resurrect writes its saves outside XDG (~/.tmux/resurrect) unless told otherwise.
    set -g @resurrect-dir '${config.xdg.stateHome}/tmux/resurrect'
    set -g @resurrect-capture-pane-contents 'on'
    set -g @resurrect-strategy-nvim 'session'
    set -g @continuum-restore 'on'
    # 1 is continuum's minimum. zellij serializes every 60s by default, and 15 minutes of lost
    # layout was the one place where this setup was genuinely behind it.
    set -g @continuum-save-interval '1'
    run-shell ${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect/resurrect.tmux
    run-shell ${pkgs.tmuxPlugins.continuum}/share/tmux-plugins/continuum/continuum.tmux
  '';
  # tmuxp starter layout. Build via `tmuxp load dev`.
  # ~/.config/tmuxp/ becomes a real directory, so you can add your own YAML alongside it.
  home.file.".config/tmuxp/dev.yaml".source = ../../../configs/terminals/tmux/tmuxp/dev.yaml;

  # herdr: AI-agent multiplexer, installed via brew in hosts/darwin.nix (not in nixpkgs), so
  # the config only lands on darwin. herdr keeps its own state (sockets, logs, session.json)
  # next to this file, so symlink the single file and leave ~/.config/herdr a real directory.
  # Only two things are pulled over from our setup — the tmux prefix and the rose-pine pair.
  # Everything else stays on herdr's defaults, which already match tmux for
  # prefix+c/x/z/e/hjkl/p/n, prefix+X (close tab) and prefix+R (reload).
  # herdr ships rose-pine/rose-pine-dawn built in, so no palette generation is needed; the
  # names are pinned for the same reason as dark/light in lib/theme.nix.
  home.file.".config/herdr/config.toml" = lib.mkIf pkgs.stdenv.isDarwin {
    text = ''
      # nix (modules/home/terminal.nix) が生成。手で編集しない。
      # 変更後は `herdr server reload-config` で反映。
      onboarding = false

      [theme]
      # tmux と同じ rose-pine。macOS の外観に追従してライト/ダークを切り替える。
      auto_switch = true
      dark_name = "rose-pine"
      light_name = "rose-pine-dawn"

      [keys]
      # tmux と同じ C-t。Emacs の C-b (backward-char) と衝突するため。
      prefix = "ctrl+t"

      [ui]
      show_agent_labels_on_pane_borders = true

      # 通知ポップアップは macOS の通知センターへ
      [ui.toast]
      delivery = "system"
    '';
  };
}
