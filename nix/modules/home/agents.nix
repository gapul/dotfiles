# AI agents component (ECS: profile). Codex/Claude config, themes, environment variables.
{
  config,
  pkgs,
  ...
}:
let
  rosePineTmThemes = import ../../lib/rose-pine-tm-theme.nix { inherit pkgs; };
in
{
  home.sessionVariables = {
    CLAUDE_CONFIG_DIR = "${config.home.homeDirectory}/.config/claude";
    CODEX_HOME = "${config.xdg.dataHome}/codex";
    CODEX_SQLITE_HOME = "${config.xdg.stateHome}/codex/sqlite";
  };

  # Codex: upstream defaults to ~/.codex, but CODEX_HOME moves it under XDG data.
  # auth/history/skills/plugins go to CODEX_HOME, SQLite is separated into CODEX_SQLITE_HOME.
  # Use an out-of-store symlink so settings updated from the TUI are reflected back into the repo.
  xdg.dataFile."codex/config.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/configs/cli/codex/config.toml";
  xdg.dataFile."codex/themes/rose-pine.tmTheme".source = "${rosePineTmThemes}/dist/rose-pine.tmTheme";
  xdg.dataFile."codex/themes/rose-pine-dawn.tmTheme".source = "${rosePineTmThemes}/dist/rose-pine-dawn.tmTheme";
}
