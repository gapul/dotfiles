# SSO for XDG-oriented exports for preset ZDOTDIR / GUI / older shells.
#
# The same exports were written as duplicate literals in .zshenv
# (nix/home/common.nix, unguarded) and programs.zsh.envExtra (nix/modules/home/shell.nix),
# so consolidate them. Fixing here makes both follow. Keep the values matching the
# config.xdg.* origin of sessionVariables (common.nix) (they point to the same real path,
# aside from absolute-path vs $HOME form differences).
#
# Do not append a trailing newline (the caller controls newline placement to keep the generated text invariant).
rec {
  codex = ''
    export CODEX_HOME="$HOME/.local/share/codex"
    export CODEX_SQLITE_HOME="$HOME/.local/state/codex/sqlite"'';

  npm = ''
    export NPM_CONFIG_USERCONFIG="$HOME/.config/npm/npmrc"
    export NPM_CONFIG_CACHE="$HOME/.cache/npm"
    export NPM_CONFIG_PREFIX="$HOME/.local/share/npm"'';

  # Everything ~/.zshenv exports besides ZDOTDIR, for every way zsh can start (non-interactive
  # `ssh host cmd`, GUI-launched shells, old shells that skip the hm-session-vars guard). Shared
  # by home/common.nix (~/.zshenv) and hosts/nixos-laptop-zsh.nix ($ZDOTDIR/.zshenv).
  guardless = ''
    # CLAUDE_CONFIG_DIR is also in home.sessionVariables, but hm-session-vars.sh's
    # __HM_SESS_VARS_SOURCED guard can skip re-sourcing and leave it empty (old shells / GUI launch).
    # To avoid that, also export it explicitly in the guard-less .zshenv.
    export CLAUDE_CONFIG_DIR="$HOME/.config/claude"
    # Codex doesn't reference the split XDG dirs directly, so use the official CODEX_HOME
    # to relocate ~/.codex under XDG data/state.
    ${codex}
    # For HISTFILE too, pin the XDG path early in the guard-less .zshenv so old/GUI-launched
    # shells that don't read .zshrc don't leak into ~/.zsh_history.
    export HISTFILE="$HOME/.local/state/zsh/history"
    # Same for GNUPGHOME. Running gpg from a zsh where it's unset regenerates an empty
    # ~/.gnupg, so pin it early in the guard-less .zshenv.
    export GNUPGHOME="$HOME/.local/share/gnupg"
    # A host that can't log Claude Code in through a browser keeps a long-lived OAuth token in
    # this file instead (the headless mini: its keychain only opens for the console session).
    # It goes here rather than in .zshrc because `ssh host 'cmd'` reads only .zshenv, and every
    # agent that reaches such a host arrives exactly that way. Absent on machines that log in
    # normally, where the keychain already answers.
    [ -r "$HOME/.config/claude/oauth-token" ] && \
      export CLAUDE_CODE_OAUTH_TOKEN="$(cat "$HOME/.config/claude/oauth-token")"
    # npm too: pin its non-XDG defaults (~/.npmrc / ~/.npm) via env vars.
    ${npm}
    if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
      # nix-daemon.sh prints a "safely delete either" warning to stderr when both
      # ~/.nix-profile and the new profile exist. Both symlinks are kept intentionally,
      # so just swallow the warning (exports survive since it's sourced).
      . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 2>/dev/null
    fi
    [ -f "$HOME/.local/state/nix/profile/etc/profile.d/hm-session-vars.sh" ] && \
      . "$HOME/.local/state/nix/profile/etc/profile.d/hm-session-vars.sh"'';
}
