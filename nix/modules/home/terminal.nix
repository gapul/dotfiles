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
    run ${pkgs.coreutils}/bin/mkdir -p "${config.xdg.dataHome}/terminfo"
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
    if pkgs.stdenv.hostPlatform.isDarwin then
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
  #
  # The body lives in configs/ rather than inline here, so that hosts reached with nssh get it
  # too: there ~/.config/tmux is a symlink into the repo, and home-manager never runs. Keeping
  # it inline meant prefix+e was bound but the script was absent on every remote.
  home.file.".config/tmux/scrollback-edit.sh" = {
    executable = true;
    source = ../../../configs/terminals/tmux/scrollback-edit.sh;
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

  # herdr: AI-agent multiplexer (package in modules/home/packages.nix). Config goes to every
  # host, not just darwin, because `herdr --remote <host>` refuses to attach unless both ends
  # run the same build: the client looks for a matching herdr on the remote PATH (nix profile
  # paths included) and otherwise offers to drop its own copy into ~/.local/bin. Declaring the
  # package on both sides keeps that fallback from ever firing — the flake pin is what holds
  # the two versions together. herdr keeps its own state (sockets, logs, session.json) next to
  # this file, so place the single file and leave ~/.config/herdr a real directory.
  # Keys stay on herdr's own defaults — the prefix is the only thing pulled over from tmux,
  # because it is the one key the fingers hit before herdr is even in the picture (and C-b
  # collides with Emacs). Many of the rest already agree anyway (c, x, z, e, hjkl, p, n, ?, R).
  # herdr ships rose-pine/rose-pine-dawn built in, so no palette generation is needed; the
  # names are pinned for the same reason as dark/light in lib/theme.nix.
  # The contents are in configs/cli/herdr/config.toml. Only the main Mac goes through
  # home-manager, so writing it inline via .text here means it never reaches remotes (real
  # damage on 2026-08-15: auto_switch defaults to false, so theme following on remote herdr
  # didn't work at all). Keeping it in a file lets configs/bin/remote-bootstrap link the same one.
  home.file.".config/herdr/config.toml".source = ../../../configs/cli/herdr/config.toml;

  # Vim-style keys for terminal-browser. Extensions (Surfingkeys) can't be installed: it
  # doesn't expose Electron's loadExtension, so there's no path to load an extension at all.
  # Instead, `--preload` injects into an isolated world before the page loads. The path is
  # passed by the bin wrapper in pkgs/terminal-browser.nix, only for open / new-tab.
  # Without this file nothing is added, so deleting it returns to plain terminal-browser.
  home.file.".config/terminal-browser/vimkeys.js".source =
    ../../../configs/cli/terminal-browser/vimkeys.js;
  home.file.".config/terminal-browser/main.js".source = ../../../configs/cli/terminal-browser/main.js;

  # Prepare the remote before `herdr --remote <host>`.
  #
  # nssh has two stages, "prepare over ssh -> start tmux", but herdr's --remote opens its own
  # ssh, so the first stage is missing. As a result, only hosts entered via herdr don't get
  # dotfiles updated, and get used without nix-portable, symlinks, or Claude settings
  # (found on 2026-08-15 that ~/.dotfiles was 15 commits behind; #309-#323 hadn't arrived).
  # To close this without changing the habit of typing plain `herdr`, shadow it with a
  # function of the same name.
  #
  # Without --remote (local launch) it passes straight through. Matching is exact.
  # There's a separate flag --remote-keybindings, so a partial match would misfire.
  # A failed preparation doesn't stop the connection (you can't fix it without connecting).
  #
  # Don't branch on HERDR_ENV. Typing `herdr --remote` inside a herdr session isn't rejected
  # as nesting and connects as is (measured 2026-08-15; it gets as far as remote platform
  # detection), so skipping because we're inside would drop the preparation on exactly the
  # most likely path: moving from the main Mac's herdr to a remote.
  programs.zsh.initContent = lib.mkAfter ''
    function herdr() {
      local target="" arg bootstrap url
      local -i i=0
      for arg in "$@"; do
        (( i++ ))
        case "$arg" in
          --remote)   target="''${@[i+1]}" ; break ;;
          --remote=*) target="''${arg#--remote=}" ; break ;;
        esac
      done
      # 値が無い / 次のトークンがフラグ、は --remote の指定漏れ。herdr 本体に叱らせる。
      [[ "$target" == -* ]] && target=""
      if [[ -n "$target" ]]; then
        bootstrap="$HOME/.local/bin/remote-bootstrap"
        [[ -r "$bootstrap" ]] || bootstrap="$HOME/.dotfiles/configs/bin/remote-bootstrap"
        if [[ -r "$bootstrap" ]]; then
          url=$(command git -C "$HOME/.dotfiles" remote get-url origin 2>/dev/null)
          [[ -n "$url" ]] || url="git@github.com:gapul/dotfiles.git"
          print -u2 "[herdr] $target の下準備 (dotfiles 同期) ..."
          command ssh -A -o ConnectTimeout=10 "$target" \
            "DOTFILES_URL='$url' bash -s" < "$bootstrap" \
            || print -u2 "[herdr] WARNING: 下準備に失敗しました。そのまま接続します。"
        else
          print -u2 "[herdr] WARNING: remote-bootstrap が見つからないので下準備を飛ばします。"
        fi
      fi
      command herdr "$@"
    }
  '';
}
