# SSO for XDG-oriented exports for preset ZDOTDIR / GUI / older shells.
#
# The same exports were written as duplicate literals in .zshenv
# (nix/home/common.nix, unguarded) and programs.zsh.envExtra (nix/modules/home/shell.nix),
# so consolidate them. Fixing here makes both follow. Keep the values matching the
# config.xdg.* origin of sessionVariables (common.nix) (they point to the same real path,
# aside from absolute-path vs $HOME form differences).
#
# Do not append a trailing newline (the caller controls newline placement to keep the generated text invariant).
{
  codex = ''
    export CODEX_HOME="$HOME/.local/share/codex"
    export CODEX_SQLITE_HOME="$HOME/.local/state/codex/sqlite"'';

  npm = ''
    export NPM_CONFIG_USERCONFIG="$HOME/.config/npm/npmrc"
    export NPM_CONFIG_CACHE="$HOME/.cache/npm"
    export NPM_CONFIG_PREFIX="$HOME/.local/share/npm"'';
}
