{
  config,
  pkgs,
  ...
}:
let
  c = import ../lib/theme.nix; # アクティブテーマのパレット (common.nix と同じ SSO)

  # zellij テーマ kdl を palette p から生成 (common.nix の実装を踏襲)。
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
  # ヘッドレス mac mini 向けの最小 home 環境。
  # ワークステーション (home/common.nix) の巨大な CLI 一式や sops 依存は持ち込まず、
  # SSH 作業で使う 4 ツール (zellij / neovim / lazygit / yazi) とその設定だけを
  # workstation と同じ dotfiles/configs から継承する。age 鍵不要・攻撃面最小。
  home.stateVersion = "23.11";
  programs.home-manager.enable = true;
  manual.manpages.enable = false;
  manual.json.enable = false;

  # 4 ツール本体 + これらが直接呼ぶ必須 CLI 依存のみ (telescope の grep/find, fuzzy)。
  home.packages = with pkgs; [
    zellij
    neovim
    yazi
    ripgrep
    fd
    fzf

    # ccm: mac mini での Claude Code 既定起動形。
    # Remote Control(名前 dotfiles) + 直前会話の継続 + 全許可スキップ(YOLO) +
    # ~/.dotfiles へのアクセス許可。claude 本体は上書きしない (auth/update/agents を壊さない)。
    # 注意: --dangerously-skip-permissions は NOPASSWD sudo と併用で root まで無 gate。
    (writeShellScriptBin "ccm" ''
      exec "$HOME/.local/bin/claude" \
        --remote-control dotfiles \
        --continue \
        --dangerously-skip-permissions \
        --add-dir "$HOME/.dotfiles" \
        "$@"
    '')
  ];

  # lazygit: workstation と同じ ANSI テーマ設定を継承 (本体パッケージも HM が入れる)。
  programs.lazygit = {
    enable = true;
    settings.gui.theme = {
      activeBorderColor = [
        "magenta"
        "bold"
      ];
      inactiveBorderColor = [ "blue" ];
      optionsTextColor = [ "cyan" ];
      selectedLineBgColor = [ "blue" ];
      cherryPickedCommitBgColor = [ "magenta" ];
      cherryPickedCommitFgColor = [ "blue" ];
      unstagedChangesColor = [ "red" ];
      defaultFgColor = [ "default" ];
    };
  };

  # 設定は dotfiles/configs から継承 (workstation と同一実体)。
  home.file.".config/zellij" = {
    source = ../../configs/terminals/zellij;
    recursive = true;
  };
  home.file.".config/zellij/themes/rose-pine.kdl".text = mkZellijTheme "rose-pine" c.dark;
  home.file.".config/zellij/themes/rose-pine-dawn.kdl".text = mkZellijTheme "rose-pine-dawn" c.light;

  home.file.".config/yazi" = {
    source = ../../configs/cli/yazi;
    recursive = true;
  };

  # nvim は dotfiles に直接書き戻せるよう out-of-store symlink (workstation と同じ機構)。
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/configs/editors/nvim";

  # XDG Base Directory: SSH セッション/ccm から起動される CLI 向けに、ガード無しの
  # .zshenv で常に export (workstation common.nix と同じ方針の最小版)。
  # claude は native install (~/.local/bin/claude) のため CLAUDE_CONFIG_DIR で
  # ~/.claude を XDG config 配下へ寄せる (auth .credentials.json も同居して移設済み)。
  home.file.".zshenv" = {
    force = true;
    text = ''
      export XDG_CONFIG_HOME="$HOME/.config"
      export XDG_DATA_HOME="$HOME/.local/share"
      export XDG_STATE_HOME="$HOME/.local/state"
      export XDG_CACHE_HOME="$HOME/.cache"
      export CLAUDE_CONFIG_DIR="$HOME/.config/claude"
      export MPLCONFIGDIR="$HOME/.config/matplotlib"
    '';
  };
}
