# AI agents component (ECS: profile)。Codex/Claude の config・テーマ・環境変数。
{
  config,
  ...
}:
{
  home.sessionVariables = {
    CLAUDE_CONFIG_DIR = "${config.home.homeDirectory}/.config/claude";
    CODEX_HOME = "${config.xdg.dataHome}/codex";
    CODEX_SQLITE_HOME = "${config.xdg.stateHome}/codex/sqlite";
  };

  # Codex: 上流は ~/.codex 既定だが、CODEX_HOME で XDG data 配下へ移す。
  # auth/history/skills/plugins は CODEX_HOME、SQLite は CODEX_SQLITE_HOME に分離。
  # TUI から設定が更新されても repo に反映されるよう out-of-store symlink にする。
  xdg.dataFile."codex/config.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/configs/cli/codex/config.toml";
  xdg.dataFile."codex/themes/rose-pine.tmTheme".source =
    ../../../configs/cli/bat/themes/rose-pine.tmTheme;
  xdg.dataFile."codex/themes/rose-pine-dawn.tmTheme".source =
    ../../../configs/cli/bat/themes/rose-pine-dawn.tmTheme;
}
